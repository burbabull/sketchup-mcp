require 'sketchup'
require 'json'
require 'socket'
require 'fileutils'
require 'timeout'

# Create a more robust initialization lock using multiple mechanisms
INIT_LOCK_FILE = File.join(File.dirname(__FILE__), '.mcp_init_lock')
INIT_TIMESTAMP = Time.now.to_f

# Check multiple conditions to prevent duplicate loading
already_loaded = false

# Check 1: Global variable
if defined?($sketchup_mcp_initialized) && $sketchup_mcp_initialized
  already_loaded = true
  puts "MCP Extension already loaded (global variable check)"
end

# Check 2: File-based lock with timestamp
if File.exist?(INIT_LOCK_FILE)
  lock_time = File.read(INIT_LOCK_FILE).to_f rescue 0
  if (Time.now.to_f - lock_time) < 10.0  # Within last 10 seconds
    already_loaded = true
    puts "MCP Extension already loaded (file lock check, #{Time.now.to_f - lock_time} seconds ago)"
  else
    puts "Stale lock file found, removing..."
    File.delete(INIT_LOCK_FILE) rescue nil
  end
end

# Check 3: Module constant
begin
  if defined?(SketchupMCP) && defined?(SketchupMCP::INITIALIZED) && SketchupMCP::INITIALIZED
    already_loaded = true
    puts "MCP Extension already loaded (module constant check)"
  end
rescue
  # Module not defined yet, continue
end

puts "MCP Extension loading... (timestamp: #{INIT_TIMESTAMP})"
SKETCHUP_CONSOLE.show rescue nil

unless already_loaded
  puts "Initializing MCP Server... (first time, #{INIT_TIMESTAMP})"
  puts "Loading from: #{__FILE__}"
  
  # Create lock file immediately
  begin
    File.write(INIT_LOCK_FILE, INIT_TIMESTAMP.to_s)
  rescue => e
    puts "Warning: Could not create lock file: #{e.message}"
  end
  
  # Mark as initialized immediately with global variable
  $sketchup_mcp_initialized = INIT_TIMESTAMP
  
  # Require all extension files (only after lock is established)
  require_relative 'server'
  
  # Require helpers
  require_relative 'helpers/logging'
  require_relative 'helpers/validation'
  require_relative 'helpers/ruby_eval'
  require_relative 'helpers/operations'
  
  # Require tools
  require_relative 'tools/component_tools'
  require_relative 'tools/boolean_tools'
  require_relative 'tools/woodworking_tools'
  require_relative 'tools/edge_tools'
  require_relative 'tools/material_tools'
  require_relative 'tools/export_tools'
  require_relative 'tools/measurement_tools'
  
  module SketchupMCP
    # Set module constant as backup
    INITIALIZED = INIT_TIMESTAMP
    LOAD_PATH = __FILE__
    
    @server = Server.new
    puts "MCP Server instance created (#{INIT_TIMESTAMP})"
    
    # Only create menu if it doesn't already exist
    begin
      plugins_menu = UI.menu("Plugins")
      mcp_menu = nil
      
      # Check if MCP Server submenu already exists
      plugins_menu.each { |item| 
        if item.to_s.include?("MCP Server")
          mcp_menu = item
          break
        end
      } rescue nil
      
      # Only create menu if it doesn't exist
      unless mcp_menu
        mcp_menu = plugins_menu.add_submenu("MCP Server")
        mcp_menu.add_item("Start Server") { SketchupMCP.get_server&.start }
        mcp_menu.add_item("Stop Server") { SketchupMCP.get_server&.stop }
        mcp_menu.add_item("Server Status") { SketchupMCP.get_server&.status }
        puts "MCP Server menu created (#{INIT_TIMESTAMP})"
      else
        puts "MCP Server menu already exists, skipping creation (#{INIT_TIMESTAMP})"
      end
    rescue StandardError => e
      puts "Error creating menu: #{e.message}"
    end
    
    # Auto-start the server when the extension loads
    puts "Attempting to auto-start MCP server... (#{INIT_TIMESTAMP})"
    
    begin
      @server.start
      puts "MCP Server auto-start completed (#{INIT_TIMESTAMP})"
    rescue StandardError => e
      puts "Failed to auto-start MCP server: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
    end
    
    # Module methods for accessing the server instance
    def self.get_server
      @server
    end
    
    def self.initialized?
      defined?(INITIALIZED) && INITIALIZED
    end
    
    def self.init_timestamp
      INITIALIZED
    end
    
    # Add cleanup for extension uninstall
    def self.cleanup
      if @server
        @server.cleanup
        @server = nil
      end
      $sketchup_mcp_initialized = false
      File.delete(INIT_LOCK_FILE) rescue nil
    end
    
    # Handle extension unload
    def self.unload
      cleanup
    end
    
    # Mark file as loaded using the original mechanism as well
    file_loaded(__FILE__)
  end
  
  # Clean up lock file after successful initialization
  UI.start_timer(5.0, false) do
    File.delete(INIT_LOCK_FILE) rescue nil
  end
else
  puts "MCP Extension already initialized, skipping duplicate load"
  puts "Global var state: #{$sketchup_mcp_initialized}"
  puts "Loading from: #{__FILE__}"
end 