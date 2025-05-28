# SketchUp MCP Server

A Model Context Protocol (MCP) server that enables Claude AI to interact directly with SketchUp, allowing for automated 3D modeling, woodworking joint creation, component manipulation, and more.

## Overview

This project bridges SketchUp and Claude AI through the Model Context Protocol, enabling natural language 3D modeling workflows. You can describe what you want to create, and Claude will generate the appropriate SketchUp geometry using the available tools.

## Features

### Core 3D Modeling
- **Component Creation**: Create cubes, cylinders, spheres, and cones with precise positioning
- **Transform Operations**: Move, rotate, and scale components
- **Material Assignment**: Apply materials and colors to components
- **Selection Management**: Query and manipulate selected components
- **Scene Export**: Export models in various formats (SKP, DAE, OBJ, STL, PNG, JPG)

### Advanced Positioning & Measurement
- **Enhanced Positioning**: Multiple origin modes (center, bottom_center, top_center, min_corner, max_corner)
- **Directional Control**: Specify extrusion direction (up, down, forward, back, right, left)
- **Distance Calculations**: Measure distances between points and components
- **Component Inspection**: Get detailed information about any component
- **Relative Positioning**: Position components relative to each other
- **Snap & Align**: Automatically align components with various alignment types

### Woodworking Joints
- **Mortise & Tenon Joints**: Create traditional woodworking joints
- **Dovetail Joints**: Generate dovetail connections with customizable angles
- **Finger Joints**: Create box joints with adjustable finger counts

### Visual Aids & References
- **Reference Markers**: Create visual reference points for precise positioning
- **Grid Systems**: Generate grid references for layout work
- **Bounding Box Visualization**: Show component bounds and wireframes
- **Position Preview**: Preview component placement before creation

### Development & Scripting
- **Ruby Code Execution**: Run arbitrary Ruby code within SketchUp
- **Component Querying**: List all components with filtering options

## Installation

### Prerequisites
- SketchUp 2017 or later
- Claude Desktop app
- macOS, Windows, or Linux with Ruby support

### Step 1: Build the Extension

Use the provided build script to create the SketchUp extension:

```bash
chmod +x create_rbz.sh
./create_rbz.sh
```

This creates a `sketchup_mcp_server_v1.7.0.rbz` file.

### Step 2: Install in SketchUp

1. Open SketchUp
2. Go to **Window > Extension Manager**
3. Click **Install Extension**
4. Select the generated `.rbz` file
5. Click **Install**

### Step 3: Configure Claude Desktop

Add the MCP server to your Claude Desktop configuration. Edit your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "python",
      "args": ["/path/to/your/src/sketchup_mcp/server.py"]
    }
  }
}
```

## Usage

### Starting the Server

The MCP server auto-starts when SketchUp launches. You can also manually control it:

1. In SketchUp, go to **Plugins > MCP Server**
2. Use the menu to start/stop the server
3. The server listens on `localhost:9876`

### Basic Examples

#### Creating Components
```
"Create a 10x5x2 cube at position [50, 25, 10]"
"Make a cylinder with diameter 8 and height 15, positioned at the origin with bottom-center alignment"
```

#### Positioning & Alignment
```
"Position the new component to the right of the existing cube"
"Align these two components center-to-center"
"Create a grid system with 10-unit spacing"
```

#### Woodworking Joints
```
"Create a mortise and tenon joint between these two boards"
"Make a dovetail joint with 6 tails and 15-degree angle"
```

#### Measurements & Analysis
```
"Measure the distance between these two components"
"Show me the bounding boxes of all selected components"
"Inspect this component and tell me its dimensions"
```

### Component Types

- **cube**: Rectangular prisms with width, height, depth
- **cylinder**: Circular cylinders with diameter and height  
- **sphere**: Spherical shapes with diameter
- **cone**: Conical shapes with base diameter and height

### Positioning Modes

- **center**: Position specifies the center point (default)
- **bottom_center**: Position specifies bottom-center (useful for placing on surfaces)
- **top_center**: Position specifies top-center (useful for hanging objects)
- **min_corner**: Position specifies minimum corner (x_min, y_min, z_min)
- **max_corner**: Position specifies maximum corner (x_max, y_max, z_max)

### Direction Control

- **up**: Extrude upward (positive Z)
- **down**: Extrude downward (negative Z)
- **forward**: Extrude forward (positive Y)
- **back**: Extrude backward (negative Y)
- **right**: Extrude right (positive X)
- **left**: Extrude left (negative X)

## Available Tools

### Component Management
- `create_component` - Create new 3D components with advanced positioning
- `delete_component` - Remove components by ID
- `transform_component` - Move, rotate, scale components
- `get_selection` - Get currently selected components
- `set_material` - Apply materials to components
- `inspect_component` - Get detailed component information
- `query_all_components` - List all components in the model

### Positioning & Measurement
- `calculate_distance` - Distance between 3D points
- `measure_components` - Distances between components
- `snap_align_component` - Align components automatically
- `position_relative_to_component` - Position relative to another component
- `position_between_components` - Position between two components
- `preview_position` - Preview placement before creation

### Visual Aids
- `create_reference_markers` - Visual reference points
- `clear_reference_markers` - Remove reference markers
- `create_grid_system` - Generate layout grids
- `show_component_bounds` - Visualize bounding boxes

### Woodworking Joints
- `create_mortise_tenon` - Traditional mortise and tenon joints
- `create_dovetail` - Dovetail joints with customizable parameters
- `create_finger_joint` - Box joints (finger joints)

### Export & Scripting
- `export_scene` - Export to various formats
- `eval_ruby` - Execute Ruby code in SketchUp

## Development

### File Structure
```
├── create_rbz.sh              # Build script for the extension
├── src/sketchup_mcp/
│   └── server.py              # MCP server implementation
├── su_mcp.rb                  # SketchUp extension entry point
└── su_mcp/
    ├── main.rb                # Main extension logic
    ├── server.rb              # Socket server for MCP communication
    ├── helpers/               # Helper modules
    └── tools/                 # Tool implementations
```

### Communication Protocol

The extension communicates via JSON-RPC over TCP sockets:
- SketchUp extension runs a socket server on port 9876
- Python MCP server connects and sends JSON-RPC requests
- Responses include detailed success/error information

### Extending the Server

To add new tools:
1. Add the tool function to `server.py` with the `@mcp.tool()` decorator
2. Implement the corresponding Ruby handler in the SketchUp extension
3. Rebuild the extension with `./create_rbz.sh`

## Troubleshooting

### Connection Issues
- Ensure SketchUp is running and the extension is loaded
- Check that port 9876 is not blocked by firewall
- Restart both SketchUp and Claude Desktop if connection fails

### Extension Not Loading
- Verify the `.rbz` file was built correctly
- Check SketchUp's Extension Manager for error messages
- Ensure all required Ruby files are included in the package

### Performance Issues
- For complex operations, the server automatically adjusts timeouts
- Large models may require increased timeout values
- Consider breaking complex operations into smaller steps

## License

[Add your license information here]

## Contributing

[Add contributing guidelines here]

## Support

[Add support/contact information here]
