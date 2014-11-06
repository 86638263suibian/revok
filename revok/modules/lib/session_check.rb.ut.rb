require 'rexml/document'
require 'cgi'


include REXML

module Sess

  def env_prepare
    if @config['logtype'] == 'basic'
      resp=Typhoeus::Request.new(@config['target'],ssl_verifypeer: false,ssl_verifyhost: 1,).run
      if resp.code >= 300 and resp.code < 308
        resp.response_headers.match(/^\s*Location\:\s*(.*?)$/)
        @target=$1
      else
        @target = @config['target']
      end
    end
  end

  def pre_login
    if @config['logtype'] == 'normal'
      dir = @config['login']
    else
      dir = @target
    end
    log "Running pre_login before the first login..." 
    pre_resp=Typhoeus::Request.new(dir,ssl_verifypeer: false,ssl_verifyhost: 1,connecttimeout:5,).run
    #log "***pre_resp***#{pre_resp.code}#{pre_resp.headers}" 

    if pre_resp.nil?
      log "No response received" 
    elsif pre_resp.code == 404
      log "404 received, page wasn't found" 
    end
    grab_set_cookie(pre_resp)

    return pre_resp
  end #pre_login

  def login(pre_resp) #Login
    params = Hash.new()
    post_me = Hash.new()
    tokens = Array.new()
    if @config['logtype'] == 'normal'
      dir = @config['login']
    else
      dir = @target
    end

    cookie = get_cookie

    if @config['logtype'] == 'normal'
      req = @session['requests']["#{@login_request}"]
      data_format = req.split("\r\n\r\n")[1].strip
      dir = req.scan(/POST (.*?) HTTP/)[0][0].strip
      tokens = data_format.split("&")
      params = _grab_token(pre_resp, tokens) #Grab csrf and other tokens
      post_me = sess_set_post_param(params) #Prepare POST login params
      resp= Typhoeus::Request.new(
          dir,
          ssl_verifypeer: false,
          ssl_verifyhost: 1,
          method: :post,
          headers: { Cookie: sess_gen_cookie(cookie) },
          body: post_me,
          followlocation: true,
        ).run
    else
      @auth = Rex::Text.encode_base64("#{@config['username']}:#{@config['password']}")
      resp= Typhoeus::Request.new(
          dir,
          ssl_verifypeer: false,
          ssl_verifyhost: 1,
          method: :get,
          headers: { Cookie: sess_gen_cookie(cookie),Authorization: "Basic " + @auth },
          followlocation: true,
        ).run
    end
    grab_set_cookie(resp)
    if (resp.code > 300 and resp.code < 310)
      resp = handle_redirection(resp)
    end
  end #login

  def handle_redirection(resp)
    redir_cnt = 0
    cookie = get_cookie
    prefix = @config['target']
    while(resp.code != 200)
      if resp.headers['Location'].include? "http"
        dir = resp.headers['Location']
      else
        dir = "#{prefix}/#{resp.headers['Location']}"
      end

      if @config['logtype'] == 'basic'
        resp=Typhoeus::Request.new(
          dir,
          method: :get,
          headers: { Cookie: sess_gen_cookie(cookie),Authorization: "Basic " + @auth },
          connecttimeout:5,
        ).run
      else
        resp=Typhoeus::Request.new(
          dir,
          method: :get,
          headers: { Cookie: sess_gen_cookie(cookie)},
          connecttimeout:5,
        ).run
      end

      grab_set_cookie(resp)
      log "Redirection request uri: #{dir}" 

      redir_cnt += 1
      if(redir_cnt == 5) #Too many redirection"
        log "More than 5 redirections occurred" 
        break
      end
    end  
  end

  def grab_set_cookie(resp) #Grab cookies to be used
    temp = Array.new()
    setcookie=resp.headers['Set-Cookie']
    if setcookie == nil
      #log "No set cookie in response header" 
      return @cookies
    end
    if setcookie.class==Array
      setcookie.each do |val|
        if val.match(/(.*?)=(.*?)(;|$)/)!=nil
          @cookies[$1]=$2
        end
      end
    else
        if setcookie.match(/(.*?)=(.*?)(;|$)/)!=nil
          @cookies[$1]=$2
        end
    end
    return @cookies
  end #grab_set_cookie

  def sess_gen_cookie(cookie_set) #Generate cookies to be used from hash
    cookies = ""
    if cookie_set == nil
      return cookies
    end
    cookie_set.each_pair do |k,v|
       cookies += "#{k}=#{v};"
    end
    return cookies
  end

  def sess_set_post_param(params)
    post_param = Hash.new()
    params.each_pair do |k,v|
      post_param[k] = v
    end
    return post_param
  end

  def _grab_token(resp, tokens) #Grab csrf and other tokens
    params = Hash.new()
    begin
      tokens.each do |token|
        k = Rex::Text::uri_decode(token.split("=")[0].strip)
        v = Rex::Text::uri_decode(token.split("=")[1].strip)
        if (v == @config['username']) or (v == @config['password'])
          params[k] = v
          next
        else
          tokenArr1 = resp.body.scan(/<input.*?name="#{k}".*?value="(.*?)".*?>|<input.*?value="(.*?)".*?name="#{k}".*?>/)
          tokenArr1 = tokenArr1[0].compact if tokenArr1 != []
          tokenArr2 = resp.body.scan(/<input.*?name="(.*?)".*?value="#{v}".*?>|<input.*?value="#{v}".*?name="(.*?)".*?>/)
          tokenArr2 = tokenArr2[0].compact if tokenArr2 != []#For csrf token which name is need to be grabbed       
        end

        if tokenArr1.length > 0
          params[k] = tokenArr1[0]
        elsif tokenArr2.length > 0
          params[tokenArr2[0]] = v 
        end
      end
    rescue
      log "Login parameters can not be grabbed" 
    end
    return params
  end

  def compare_cookie(pre_cookie, aft_cookie)
    k = @session_id
    if (pre_cookie.has_key? k) and (aft_cookie.has_key? k) and (pre_cookie[k] != aft_cookie[k])
      #log "The cookie is changed after login" 
      return false
    else
      #log "The cookie is not changed after login" 
      return true
    end
  end

  def get_cookie
    @cookies
  end 

  def sess_fix
    @cookies = Hash.new()
    env_prepare
    if @config['logtype'] != "none"
      pre_resp = pre_login
      pre_cookie = @cookies.clone

      log "Checking session ID is set or not before login..." 
      if(pre_cookie.has_key? @session_id)
        log "Session ID is set before login. Login and check if it changes..." 

        login(pre_resp)
        aft_cookie = @cookies.clone

        log "pre_session is: #{pre_cookie}" 
        log "aft_session is: #{aft_cookie}" 
        is_same = compare_cookie(pre_cookie, aft_cookie)
        if is_same
          log "Login with an old session ID, and it was not reset" 
          return false
        else
          log "Login with an old session ID, and it was reset" 
        end
      else
        log "Session ID isn't set before login" 
      end
    else
      log "No authentication in this application"
    end
    return true
  end #sess_fix

end
