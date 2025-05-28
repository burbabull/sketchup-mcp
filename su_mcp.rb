require 'sketchup.rb'
require 'extensions.rb'
require 'json'
require 'socket'

module SketchupMCP
  unless file_loaded?(__FILE__)
    # Create the extension
    loader = File.join(File.dirname(__FILE__), 'su_mcp', 'main.rb')
    extension = SketchupExtension.new('SketchUp MCP Server', loader)
    
    # Set extension properties
    extension.description = 'Model Context Protocol server for SketchUp that allows AI agents to control and manipulate scenes'
    extension.version = '1.6.8'
    extension.copyright = '© 2024'
    extension.creator = 'MCP Team'
    
    # Register the extension with SketchUp
    Sketchup.register_extension(extension, true)
    
    # Mark this file as loaded
    file_loaded(__FILE__)
  end
end 