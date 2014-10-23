require_relative 'module'
require_relative 'modules'

module Revok

	class ModuleExecutor
		def initialize(modules = {})
			@modules = modules
			@exec_list = Array.new
		end

		def gen_exec_list_all
			@exec_list.clear
			if (self.modules.empty?)
				raise RuntimeError, "No any instance of modules", caller
			end
			self.modules.each {|_module|
				instance = _module[1]
				module_info = [instance.name,
								instance.info["group_name"],
								instance.info["group_priority"],
								instance.info["priority"]]
				@exec_list.push(module_info)
			}
			@exec_list.sort_by! {|name, g_name, g_priority, priority|
				[g_priority, priority]
			}
		end

		def execute
			return false if (self.exec_list.empty?)
			self.exec_list.each {|name, g_name, g_priority, priority|
				modules[name].run
			}
			return true
		end

		attr_reader		:exec_list
		attr_accessor	:modules

		private

			attr_writer		:exec_list
	end

end
