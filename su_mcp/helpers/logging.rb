module SketchupMCP
  module Logging
    def self.log(msg)
      begin
        timestamp = Time.now.strftime("%H:%M:%S.%3N")
        formatted_msg = "[#{timestamp}] MCP: #{msg}"
        
        # Try multiple ways to output the log message
        puts formatted_msg
        
        begin
          SKETCHUP_CONSOLE.write("#{formatted_msg}\n")
        rescue
          begin
            Sketchup.send_action("showRubyPanel:")
            SKETCHUP_CONSOLE.write("#{formatted_msg}\n")
          rescue
            # If all else fails, just use puts
          end
        end
      rescue StandardError => e
        puts "MCP LOG ERROR: #{e.message}"
      end
      STDOUT.flush
    end
  end
end 