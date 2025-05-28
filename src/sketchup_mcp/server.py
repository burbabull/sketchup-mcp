from mcp.server.fastmcp import FastMCP, Context
import socket
import json
import asyncio
import logging
from dataclasses import dataclass
from contextlib import asynccontextmanager
from typing import AsyncIterator, Dict, Any, List
import time

# Configure logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("SketchupMCPServer")

# Define version directly to avoid pkg_resources dependency
__version__ = "0.1.17"
logger.info(f"SketchupMCP Server version {__version__} starting up")

@dataclass
class SketchupConnection:
    host: str
    port: int
    sock: socket.socket = None
    
    def connect(self) -> bool:
        """Connect to the Sketchup extension socket server"""
        logger.info(f"=== CONNECT START: Attempting to connect to {self.host}:{self.port} ===")
        
        if self.sock:
            logger.info("Existing socket found, testing connection...")
            try:
                # Test if connection is still alive
                logger.info("Setting timeout for existing socket test...")
                self.sock.settimeout(0.1)
                logger.info("Sending test byte...")
                self.sock.send(b'')
                logger.info("Existing connection test passed")
                return True
            except (socket.error, BrokenPipeError, ConnectionResetError) as e:
                # Connection is dead, close it and reconnect
                logger.info(f"Connection test failed ({str(e)}), reconnecting...")
                self.disconnect()
            
        try:
            logger.info("Creating new socket...")
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            logger.info("Socket created successfully")
            
            # Set socket options to prevent hanging
            logger.info("Setting socket options...")
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            logger.info("SO_REUSEADDR set")
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            logger.info("TCP_NODELAY set")
            self.sock.settimeout(10.0)  # 10 second timeout
            logger.info("Socket timeout set to 10.0 seconds")
            
            logger.info(f"About to call connect() to {self.host}:{self.port}...")
            self.sock.connect((self.host, self.port))
            logger.info(f"connect() call completed - TCP connection established!")
            
            # Set a longer timeout for actual operations
            logger.info("Setting longer timeout for operations...")
            self.sock.settimeout(30.0)
            logger.info("Operational timeout set to 30.0 seconds")
            
            logger.info("=== CONNECT SUCCESS: Connection established successfully ===")
            return True
        except Exception as e:
            logger.error(f"=== CONNECT FAILED: {str(e)} ===")
            self.sock = None
            return False
    
    def disconnect(self):
        """Disconnect from the Sketchup extension"""
        if self.sock:
            try:
                self.sock.close()
            except Exception as e:
                logger.error(f"Error disconnecting from Sketchup: {str(e)}")
            finally:
                self.sock = None

    def receive_full_response(self, sock, buffer_size=8192):
        """Receive the complete response, potentially in multiple chunks"""
        chunks = []
        sock.settimeout(30.0)  # Increased timeout for better reliability
        
        try:
            response_start_time = time.time()
            max_response_time = 120.0  # Maximum 2 minutes to receive complete response
            
            while time.time() - response_start_time < max_response_time:
                try:
                    chunk = sock.recv(buffer_size)
                    if not chunk:
                        if not chunks:
                            logger.warning("Connection closed before receiving any data")
                            raise Exception("Connection closed before receiving any data")
                        logger.info("Received end of response (no more data)")
                        break
                    
                    chunks.append(chunk)
                    logger.debug(f"Received chunk of {len(chunk)} bytes")
                    
                    try:
                        data = b''.join(chunks)
                        response_text = data.decode('utf-8')
                        
                        # Check if we have a complete JSON response
                        json.loads(response_text)
                        logger.info(f"Received complete response ({len(data)} bytes)")
                        return data
                    except json.JSONDecodeError:
                        # Not complete yet, continue receiving
                        continue
                    except UnicodeDecodeError:
                        # Partial UTF-8 sequence, continue receiving
                        continue
                        
                except socket.timeout:
                    logger.warning("Socket timeout during chunked receive")
                    # Check if we have partial data and can parse it
                    if chunks:
                        try:
                            data = b''.join(chunks)
                            response_text = data.decode('utf-8')
                            json.loads(response_text)
                            logger.info("Timeout occurred but received complete response")
                            return data
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            logger.warning("Timeout with incomplete data, continuing...")
                            continue
                    else:
                        logger.warning("Timeout with no data received")
                        break
                except (ConnectionError, BrokenPipeError, ConnectionResetError) as e:
                    logger.error(f"Socket connection error during receive: {str(e)}")
                    if chunks:
                        logger.info("Connection lost but attempting to parse received data...")
                        try:
                            data = b''.join(chunks)
                            response_text = data.decode('utf-8')
                            json.loads(response_text)
                            logger.info("Successfully parsed data despite connection loss")
                            return data
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            pass
                    raise
                    
        except socket.timeout:
            logger.warning("Overall timeout during chunked receive")
        except Exception as e:
            logger.error(f"Error during receive: {str(e)}")
            raise
            
        # Try to parse what we have
        if chunks:
            data = b''.join(chunks)
            logger.info(f"Attempting to parse received data ({len(data)} bytes)")
            try:
                response_text = data.decode('utf-8')
                json.loads(response_text)
                logger.info("Successfully parsed received data")
                return data
            except json.JSONDecodeError as e:
                logger.error(f"Incomplete JSON response received: {str(e)}")
                logger.error(f"Raw data (first 500 chars): {response_text[:500]}")
                raise Exception("Incomplete JSON response received")
            except UnicodeDecodeError as e:
                logger.error(f"Invalid UTF-8 in response: {str(e)}")
                raise Exception("Invalid response encoding")
        else:
            logger.error("No data received")
            raise Exception("No data received")

    def send_command(self, method: str, params: Dict[str, Any] = None, request_id: Any = None) -> Dict[str, Any]:
        """Send a JSON-RPC request to Sketchup and return the response"""
        # Try to connect if not connected
        if not self.connect():
            raise ConnectionError("Not connected to Sketchup")
        
        # Ensure we're sending a proper JSON-RPC request
        if method == "tools/call" and params and "name" in params and "arguments" in params:
            # This is already in the correct format
            request = {
                "jsonrpc": "2.0",
                "method": method,
                "params": params,
                "id": request_id
            }
        else:
            # This is a direct command - convert to JSON-RPC
            command_name = method
            command_params = params or {}
            
            # Log the conversion
            logger.info(f"Converting direct command '{command_name}' to JSON-RPC format")
            
            request = {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {
                    "name": command_name,
                    "arguments": command_params
                },
                "id": request_id
            }
        
        # Determine appropriate timeout based on operation
        operation_timeout = 120.0  # Default 2 minutes
        if method == "tools/call" and params:
            tool_name = params.get("name")
            if tool_name == "create_component":
                operation_timeout = 60.0  # 1 minute for component creation
            elif tool_name in ["boolean_operation", "create_dovetail", "create_mortise_tenon", "create_finger_joint"]:
                operation_timeout = 180.0  # 3 minutes for complex operations
            elif tool_name == "eval_ruby":
                operation_timeout = 300.0  # 5 minutes for Ruby evaluation
        
        # Maximum number of retries
        max_retries = 3  # Increased from 2
        retry_count = 0
        
        while retry_count <= max_retries:
            try:
                logger.info(f"Sending JSON-RPC request (attempt {retry_count + 1}/{max_retries + 1}): {request}")
                
                # Log the exact bytes being sent
                request_bytes = json.dumps(request).encode('utf-8') + b'\n'
                logger.info(f"Raw bytes being sent: {request_bytes}")
                
                # Send with increased timeout for socket operations
                self.sock.settimeout(30.0)
                self.sock.sendall(request_bytes)
                logger.info(f"Request sent, waiting for response...")
                
                # Set longer timeout for receiving response
                self.sock.settimeout(operation_timeout)
                
                # Handle potentially multiple responses for long-running operations
                final_result = None
                operation_id = None
                start_time = time.time()
                
                while time.time() - start_time < operation_timeout:
                    try:
                        response_data = self.receive_full_response(self.sock)
                        logger.info(f"Received {len(response_data)} bytes of data")
                        
                        response = json.loads(response_data.decode('utf-8'))
                        logger.info(f"Response parsed: {response}")
                        
                        # Check if this is an error response
                        if "error" in response:
                            logger.error(f"Sketchup error: {response['error']}")
                            raise Exception(response["error"].get("message", "Unknown error from Sketchup"))
                        
                        # Check if this is a status update for a long-running operation
                        if response.get("method") == "operation/status":
                            status_params = response.get("params", {})
                            operation_id = status_params.get("operation_id")
                            status = status_params.get("status")
                            message = status_params.get("message", "")
                            
                            logger.info(f"Operation {operation_id} status: {status} - {message}")
                            
                            if status == "failed":
                                raise Exception(f"Operation failed: {message}")
                            elif status == "completed":
                                # This shouldn't happen in status updates, but handle it
                                logger.info("Operation completed via status update")
                                return status_params.get("result", {})
                            # For "running" status, continue waiting
                            continue
                        
                        # Check if this is a final result response
                        elif "result" in response and response.get("id") == request_id:
                            logger.info("Received final result response")
                            return response.get("result", {})
                        
                        # If we get here, it might be an unexpected response
                        logger.warning(f"Unexpected response format: {response}")
                        
                    except socket.timeout:
                        logger.info("Timeout waiting for response, checking if operation is still running...")
                        # For short operations like create_component, don't wait too long
                        if method == "tools/call" and params and params.get("name") == "create_component":
                            if time.time() - start_time > 30.0:  # Only wait 30 seconds for component creation
                                logger.warning("Component creation taking too long, timing out")
                                break
                        continue
                    except json.JSONDecodeError as e:
                        logger.error(f"Invalid JSON in response: {str(e)}")
                        continue
                
                # If we get here, we timed out waiting for the final result
                if operation_id:
                    raise Exception(f"Operation {operation_id} timed out after {operation_timeout} seconds")
                else:
                    raise Exception(f"No response received within {operation_timeout} seconds")
                
            except (socket.timeout, ConnectionError, BrokenPipeError, ConnectionResetError) as e:
                logger.warning(f"Connection error (attempt {retry_count+1}/{max_retries+1}): {str(e)}")
                retry_count += 1
                
                if retry_count <= max_retries:
                    logger.info(f"Retrying connection...")
                    self.disconnect()
                    time.sleep(min(retry_count * 0.5, 2.0))  # Progressive backoff
                    if not self.connect():
                        logger.error("Failed to reconnect")
                        continue
                else:
                    logger.error(f"Max retries reached, giving up")
                    self.sock = None
                    raise Exception(f"Connection to Sketchup lost after {max_retries+1} attempts: {str(e)}")
            
            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON response from Sketchup: {str(e)}")
                if 'response_data' in locals() and response_data:
                    logger.error(f"Raw response (first 200 bytes): {response_data[:200]}")
                raise Exception(f"Invalid response from Sketchup: {str(e)}")
            
            except Exception as e:
                logger.error(f"Error communicating with Sketchup: {str(e)}")
                # For some errors, try reconnecting
                if "Connection closed" in str(e) and retry_count < max_retries:
                    logger.info("Connection closed error, attempting reconnect...")
                    retry_count += 1
                    self.disconnect()
                    time.sleep(0.5)
                    if self.connect():
                        continue
                
                self.sock = None
                raise Exception(f"Communication error with Sketchup: {str(e)}")

# Global connection management
_sketchup_connection = None

def get_sketchup_connection():
    """Get or create a persistent Sketchup connection"""
    global _sketchup_connection
    
    if _sketchup_connection is not None:
        logger.info("Testing existing connection...")
        try:
            # Test if the socket is still valid by checking its state
            if _sketchup_connection.sock and _sketchup_connection.sock.fileno() != -1:
                logger.info("Existing connection appears valid")
                return _sketchup_connection
            else:
                logger.warning("Existing connection socket is invalid")
                _sketchup_connection = None
        except Exception as e:
            logger.warning(f"Existing connection test failed: {str(e)}")
            try:
                _sketchup_connection.disconnect()
            except:
                pass
            _sketchup_connection = None
    
    if _sketchup_connection is None:
        logger.info("Creating new connection to Sketchup...")
        _sketchup_connection = SketchupConnection(host="localhost", port=9876)
        logger.info("About to call connect()...")
        if not _sketchup_connection.connect():
            logger.error("Failed to connect to Sketchup")
            _sketchup_connection = None
            raise Exception("Could not connect to Sketchup. Make sure the Sketchup extension is running.")
        logger.info("Connect() completed successfully")
        logger.info("Created new persistent connection to Sketchup")
    
    return _sketchup_connection

@asynccontextmanager
async def server_lifespan(server: FastMCP) -> AsyncIterator[Dict[str, Any]]:
    """Manage server startup and shutdown lifecycle"""
    try:
        logger.info("SketchupMCP server starting up")
        logger.info("Server startup completed - connections will be established on demand")
        yield {}
    finally:
        logger.info("Server shutdown initiated")
        global _sketchup_connection
        if _sketchup_connection:
            logger.info("Disconnecting from Sketchup")
            _sketchup_connection.disconnect()
            _sketchup_connection = None
        logger.info("SketchupMCP server shut down")

# Create MCP server with lifespan support
mcp = FastMCP(
    "SketchupMCP",
    description="Sketchup integration through the Model Context Protocol",
    lifespan=server_lifespan
)

# Tool endpoints
@mcp.tool()
def create_component(
    ctx: Context,
    type: str = "cube",
    position: List[float] = None,
    dimensions: List[float] = None,
    direction: str = "up",
    origin_mode: str = "center"
) -> str:
    """Create a new component in Sketchup with enhanced verification, positioning feedback, and directional control
    
    Position Reference: The 'position' parameter can be interpreted in different ways based on 'origin_mode'.
    The 'direction' parameter controls which way the component extends during creation.
    
    Origin Mode Options:
    - "center" (default): position specifies the CENTER POINT of the component
    - "bottom_center": position specifies the bottom-center point (useful for placing on surfaces)
    - "top_center": position specifies the top-center point (useful for hanging from ceilings)
    - "min_corner": position specifies the minimum corner (x_min, y_min, z_min)
    - "max_corner": position specifies the maximum corner (x_max, y_max, z_max)
    
    Direction Options (for extrusion-based shapes like cubes, cylinders):
    - "up" (default): extrude in positive Z direction (upward)
    - "down": extrude in negative Z direction (downward)
    - "forward": extrude in positive Y direction 
    - "back": extrude in negative Y direction
    - "right": extrude in positive X direction
    - "left": extrude in negative X direction
    - "auto": automatically determine best direction (usually up)
    
    Enhanced Features (always included):
    - Returns actual vs requested positioning accuracy
    - Provides detailed bounds information (min/max corners)
    - Shows positioning explanation and coordinate interpretation
    - Verifies component was created at expected location
    - Supports directional control for flexible component creation
    
    Examples:
    - Basic center placement: position=[100, 50, 10], origin_mode="center", direction="up"
    - Place on floor: position=[100, 50, 0], origin_mode="bottom_center", direction="up"
    - Hang from ceiling: position=[100, 50, 100], origin_mode="top_center", direction="down"
    - Precise corner control: position=[0, 0, 0], origin_mode="min_corner", direction="up"
    - Build leftward: position=[100, 50, 10], origin_mode="center", direction="left"
    
    Coordinate System:
    - X+ = Right, Y+ = Forward/Up (green axis), Z+ = Up (blue axis)
    - Component extends in the specified direction from the origin point
    
    Returns:
        A JSON string. On success, it includes a 'message' with a plain English summary
        and 'details' with the full structured verification data.
        On failure, it returns an error message string.
    
    Args:
        type: Component type (cube, cylinder, sphere, cone)
        position: [X, Y, Z] coordinates interpreted based on origin_mode (default: [0,0,0])
        dimensions: [width, height, depth] in SketchUp units (default: [1,1,1])
                   For cylinders: [diameter, diameter, height] or [diameter, height] (auto-converted)
        direction: Direction for extrusion ("up", "down", "forward", "back", "right", "left", "auto")
        origin_mode: How to interpret position ("center", "bottom_center", "top_center", "min_corner", "max_corner")
    """
    try:
        logger.info(f"create_component called with type={type}, position={position}, dimensions={dimensions}, direction={direction}, origin_mode={origin_mode}, request_id={ctx.request_id}")
        
        # Validate and normalize dimensions before sending
        if dimensions is None:
            dimensions = [1, 1, 1]
        elif len(dimensions) == 2 and type == "cylinder":
            logger.info(f"Converting cylinder dimensions from {dimensions} to 3D format")
            dimensions = [dimensions[0], dimensions[0], dimensions[1]]
        elif len(dimensions) < 3:
            while len(dimensions) < 3:
                dimensions.append(dimensions[-1] if dimensions else 1.0)
            logger.info(f"Padded dimensions to 3D: {dimensions}")
        
        dimensions = [max(0.1, float(d)) for d in dimensions]
        
        # Validate direction parameter
        valid_directions = ["up", "down", "forward", "back", "right", "left", "auto"]
        if direction not in valid_directions:
            raise ValueError(f"Invalid direction '{direction}'. Must be one of: {valid_directions}")
        
        # Validate origin_mode parameter  
        valid_origin_modes = ["center", "bottom_center", "top_center", "min_corner", "max_corner"]
        if origin_mode not in valid_origin_modes:
            raise ValueError(f"Invalid origin_mode '{origin_mode}'. Must be one of: {valid_origin_modes}")
        
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_component_with_verification",
                "arguments": {
                    "type": type,
                    "position": position or [0, 0, 0],
                    "dimensions": dimensions,
                    "direction": direction,
                    "origin_mode": origin_mode
                }
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            component_id = result.get("id")
            # Use original type for the message if not found in verification (should be there though)
            comp_type_from_input = type.capitalize()
            # Get type from verification if available, otherwise default to input type
            comp_type_from_result = result.get('verification', {}).get('type', comp_type_from_input)
            if isinstance(comp_type_from_result, str): # Ensure it's a string before capitalizing
                 comp_type_for_message = comp_type_from_result.capitalize()
            else: # Fallback if type is not a string (e.g. nil/None from Ruby)
                 comp_type_for_message = comp_type_from_input

            actual_center = result.get('verification', {}).get('bounds', {}).get('center', 'N/A')
            bounds_data = result.get('verification', {}).get('bounds', {})
            dims_str = "N/A"
            if bounds_data and all(k in bounds_data for k in ['width', 'height', 'depth']):
                # Ensure values are converted to floats before formatting
                width = float(bounds_data.get('width', 0)) if bounds_data.get('width') is not None else 0.0
                height = float(bounds_data.get('height', 0)) if bounds_data.get('height') is not None else 0.0
                depth = float(bounds_data.get('depth', 0)) if bounds_data.get('depth') is not None else 0.0
                dims_str = f"[{width:.2f}, {height:.2f}, {depth:.2f}]"

            # Include directional info in message
            directional_info = f"Created with direction='{direction}', origin_mode='{origin_mode}'. "
            message = f"{comp_type_for_message} (ID: {component_id}) created. {directional_info}Actual center: {actual_center}, Dimensions (W,H,D): {dims_str}. {result.get('positioning_explanation', '')}"
            
            # Log the plain English message
            logger.info(f"create_component successful: {message}")
            
            return json.dumps({
                "message": message,
                "details": result 
            })
        else:
            # If Sketchup reported failure
            error_message = result.get("error", "Unknown error during component creation.")
            logger.error(f"Error in create_component (from Sketchup): {error_message}")
            return json.dumps({
                "message": f"Failed to create component: {error_message}",
                "details": result
            })

    except Exception as e:
        logger.error(f"Error in create_component (Python exception): {str(e)}")
        # Ensure this path also returns a JSON string for consistency if possible
        return json.dumps({
            "message": f"Error creating component: {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def delete_component(
    ctx: Context,
    id: str
) -> str:
    """Delete a component by its entity ID.

    Args:
        id (str): The entity ID of the component to be deleted.

    Returns:
        A JSON string. On success, includes a 'message' confirming deletion.
        On failure (e.g., ID not found), includes a 'message' and 'details'.
        If a Python exception occurs, it returns an error message string.
    """
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "delete_component",
                "arguments": {"id": id}
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            message = f"Component with ID '{id}' deleted successfully."
            logger.info(message)
            return json.dumps({"message": message, "details": result})
        elif result:
            # Sketchup processed but reported failure (e.g. ID not found)
            error_reason = result.get("message", f"Component ID '{id}' not found or another error occurred.")
            message = f"Failed to delete component with ID '{id}'. Reason: {error_reason}"
            logger.warning(message)
            return json.dumps({"message": message, "details": result})
        else:
            # Should not happen if send_command works, but as a fallback
            message = f"Received an unexpected or empty response when trying to delete component ID '{id}'."
            logger.error(message)
            return json.dumps({"message": message, "error": True, "details": None})
            
    except Exception as e:
        logger.error(f"Error in delete_component for ID '{id}': {str(e)}")
        return json.dumps({
            "message": f"Error deleting component ID '{id}': {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def transform_component(
    ctx: Context,
    id: str,
    position: List[float] = None,
    rotation: List[float] = None,
    scale: List[float] = None
) -> str:
    """Transform a component's position, rotation, or scale.
    At least one transformation (position, rotation, or scale) must be provided.

    Args:
        id (str): The entity ID of the component to transform.
        position (List[float], optional): Target [X,Y,Z] coordinates for the component's origin.
                                          Defaults to no change if None.
        rotation (List[float], optional): Target rotation as [ вокруг X, вокруг Y, вокруг Z] Euler angles in degrees.
                                          Applied in a fixed order (e.g., XYZ). Defaults to no change if None.
        scale (List[float] or float, optional): Target scale. Can be a single float for uniform scaling 
                                             (e.g., 2.0 for double size), or a list [Sx, Sy, Sz] for 
                                             per-axis scaling. Values are multipliers. Defaults to no change if None.

    Returns:
        A JSON string. On success, includes a 'message' summarizing the transformation and 'details' 
        with the full structured response from SketchUp.
        On failure, includes an error 'message' and 'details'.
    """
    try:
        sketchup = get_sketchup_connection()
        arguments = {"id": id}
        applied_transformations = []

        if position is not None:
            arguments["position"] = position
            applied_transformations.append(f"position to {position}")
        if rotation is not None:
            arguments["rotation"] = rotation
            applied_transformations.append(f"rotation to {rotation}")
        if scale is not None:
            arguments["scale"] = scale
            applied_transformations.append(f"scale to {scale}")
            
        if not applied_transformations:
            message = "No transformation (position, rotation, or scale) provided. Component not changed."
            logger.info(message)
            return json.dumps({"message": message, "details": {"success": True, "id": id, "changes_applied": False}})

        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "transform_component",
                "arguments": arguments
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            transform_summary = ", ".join(applied_transformations)
            message = f"Component ID '{id}' transformed successfully: {transform_summary}."
            # Optionally, include new state if returned: e.g., result.get('new_position')
            # For now, a generic success message based on inputs.
            logger.info(message)
            return json.dumps({"message": message, "details": result})
        elif result:
            error_reason = result.get("message", f"Component ID '{id}' not found or transform failed.")
            message = f"Failed to transform component ID '{id}'. Reason: {error_reason}"
            logger.warning(message)
            return json.dumps({"message": message, "details": result})
        else:
            message = f"Received an unexpected or empty response when trying to transform component ID '{id}'."
            logger.error(message)
            return json.dumps({"message": message, "error": True, "details": None})

    except Exception as e:
        logger.error(f"Error in transform_component for ID '{id}': {str(e)}")
        return json.dumps({
            "message": f"Error transforming component ID '{id}': {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def get_selection(ctx: Context) -> str:
    """Get currently selected components in SketchUp.

    Returns:
        A JSON string. On success, includes a 'message' listing selected components by ID and type,
        and 'details' with the full structured selection data from SketchUp.
        If no components are selected, the message will indicate this.
        On failure, an error message string is returned.
    """
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "get_selection",
                "arguments": {}
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            selected_items = result.get("selection", [])
            if selected_items:
                item_descs = []
                for item in selected_items:
                    item_id = item.get("id", "Unknown ID")
                    item_type = item.get("type", "Entity") # Assuming Sketchup provides type
                    item_descs.append(f"{item_type} (ID: {item_id})")
                message = f"Currently selected components ({len(selected_items)}): {', '.join(item_descs)}."
            else:
                message = "No components are currently selected."
            logger.info(message)
            return json.dumps({"message": message, "details": result})
        elif result: # Failure reported by Sketchup
            error_reason = result.get("message", "Failed to retrieve selection from Sketchup.")
            message = f"Could not retrieve selection. Reason: {error_reason}"
            logger.warning(message)
            return json.dumps({"message": message, "details": result})
        else:
            message = "Received an unexpected or empty response when trying to get selection."
            logger.error(message)
            return json.dumps({"message": message, "error": True, "details": None})

    except Exception as e:
        logger.error(f"Error in get_selection: {str(e)}")
        return json.dumps({
            "message": f"Error getting selection: {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def set_material(
    ctx: Context,
    id: str,
    material: str
) -> str:
    """Set material for a component by its entity ID.

    Args:
        id (str): The entity ID of the component.
        material (str): The name of the material to apply (e.g., "Wood_Cherry", "Metal_Aluminum").
                        It can also be a color name like "red", "blue", etc., if the backend supports it.

    Returns:
        A JSON string. On success, includes a 'message' confirming the material change.
        On failure, includes an error 'message' and 'details'.
    """
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "set_material",
                "arguments": {
                    "id": id,
                    "material": material
                }
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            message = f"Material for component ID '{id}' successfully set to '{material}'."
            logger.info(message)
            return json.dumps({"message": message, "details": result})
        elif result:
            error_reason = result.get("message", f"Component ID '{id}' or material '{material}' not found, or another error occurred.")
            message = f"Failed to set material '{material}' for component ID '{id}'. Reason: {error_reason}"
            logger.warning(message)
            return json.dumps({"message": message, "details": result})
        else:
            message = f"Received an unexpected or empty response when trying to set material for component ID '{id}'."
            logger.error(message)
            return json.dumps({"message": message, "error": True, "details": None})

    except Exception as e:
        logger.error(f"Error in set_material for ID '{id}' with material '{material}': {str(e)}")
        return json.dumps({
            "message": f"Error setting material for component ID '{id}': {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def export_scene(
    ctx: Context,
    format: str = "skp"
) -> str:
    """Export the current SketchUp scene to a specified file format.

    Args:
        format (str, optional): The desired export file format. 
                                Common supported formats include "skp" (SketchUp model),
                                "dae" (Collada), "obj" (Wavefront OBJ), "stl" (Stereolithography),
                                "png" (Image), "jpg" (Image). Defaults to "skp".

    Returns:
        A JSON string. On success, includes a 'message' confirming the export and providing the
        file path, along with 'details' containing the full response from SketchUp.
        On failure, includes an error 'message' and 'details'.
    """
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "export",
                "arguments": {
                    "format": format
                }
            },
            request_id=ctx.request_id
        )
        
        if result and result.get("success"):
            file_path = result.get("file_path", "An unspecified location by SketchUp")
            message = f"Scene successfully exported in {format.upper()} format. File saved to: {file_path}."
            logger.info(message)
            return json.dumps({"message": message, "details": result})
        elif result:
            error_reason = result.get("message", f"Export to {format.upper()} format failed.")
            message = f"Failed to export scene in {format.upper()} format. Reason: {error_reason}"
            logger.warning(message)
            return json.dumps({"message": message, "details": result})
        else:
            message = f"Received an unexpected or empty response when trying to export scene in {format.upper()} format."
            logger.error(message)
            return json.dumps({"message": message, "error": True, "details": None})

    except Exception as e:
        logger.error(f"Error in export_scene with format '{format}': {str(e)}")
        return json.dumps({
            "message": f"Error exporting scene in {format.upper()} format: {str(e)}",
            "error": True,
            "details": None
        })

@mcp.tool()
def create_mortise_tenon(
    ctx: Context,
    mortise_id: str,
    tenon_id: str,
    width: float = 1.0,
    height: float = 1.0,
    depth: float = 1.0,
    offset_x: float = 0.0,
    offset_y: float = 0.0,
    offset_z: float = 0.0
) -> str:
    """Create a mortise and tenon joint between two components"""
    try:
        logger.info(f"create_mortise_tenon called with mortise_id={mortise_id}, tenon_id={tenon_id}, width={width}, height={height}, depth={depth}, offsets=({offset_x}, {offset_y}, {offset_z})")
        
        sketchup = get_sketchup_connection()
        
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_mortise_tenon",
                "arguments": {
                    "mortise_id": mortise_id,
                    "tenon_id": tenon_id,
                    "width": width,
                    "height": height,
                    "depth": depth,
                    "offset_x": offset_x,
                    "offset_y": offset_y,
                    "offset_z": offset_z
                }
            },
            request_id=ctx.request_id
        )
        
        logger.info(f"create_mortise_tenon result: {result}")
        return json.dumps(result)
    except Exception as e:
        logger.error(f"Error in create_mortise_tenon: {str(e)}")
        return f"Error creating mortise and tenon joint: {str(e)}"

@mcp.tool()
def create_dovetail(
    ctx: Context,
    tail_id: str,
    pin_id: str,
    width: float = 1.0,
    height: float = 1.0,
    depth: float = 1.0,
    angle: float = 15.0,
    num_tails: int = 3,
    offset_x: float = 0.0,
    offset_y: float = 0.0,
    offset_z: float = 0.0
) -> str:
    """Create a dovetail joint between two components"""
    try:
        logger.info(f"create_dovetail called with tail_id={tail_id}, pin_id={pin_id}, width={width}, height={height}, depth={depth}, angle={angle}, num_tails={num_tails}")
        
        sketchup = get_sketchup_connection()
        
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_dovetail",
                "arguments": {
                    "tail_id": tail_id,
                    "pin_id": pin_id,
                    "width": width,
                    "height": height,
                    "depth": depth,
                    "angle": angle,
                    "num_tails": num_tails,
                    "offset_x": offset_x,
                    "offset_y": offset_y,
                    "offset_z": offset_z
                }
            },
            request_id=ctx.request_id
        )
        
        logger.info(f"create_dovetail result: {result}")
        return json.dumps(result)
    except Exception as e:
        logger.error(f"Error in create_dovetail: {str(e)}")
        return f"Error creating dovetail joint: {str(e)}"

@mcp.tool()
def create_finger_joint(
    ctx: Context,
    board1_id: str,
    board2_id: str,
    width: float = 1.0,
    height: float = 1.0,
    depth: float = 1.0,
    num_fingers: int = 5,
    offset_x: float = 0.0,
    offset_y: float = 0.0,
    offset_z: float = 0.0
) -> str:
    """Create a finger joint (box joint) between two components"""
    try:
        logger.info(f"create_finger_joint called with board1_id={board1_id}, board2_id={board2_id}, width={width}, height={height}, depth={depth}, num_fingers={num_fingers}")
        
        sketchup = get_sketchup_connection()
        
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_finger_joint",
                "arguments": {
                    "board1_id": board1_id,
                    "board2_id": board2_id,
                    "width": width,
                    "height": height,
                    "depth": depth,
                    "num_fingers": num_fingers,
                    "offset_x": offset_x,
                    "offset_y": offset_y,
                    "offset_z": offset_z
                }
            },
            request_id=ctx.request_id
        )
        
        logger.info(f"create_finger_joint result: {result}")
        return json.dumps(result)
    except Exception as e:
        logger.error(f"Error in create_finger_joint: {str(e)}")
        return f"Error creating finger joint: {str(e)}"

@mcp.tool()
def eval_ruby(
    ctx: Context,
    code: str
) -> str:
    """Evaluate arbitrary Ruby code in Sketchup"""
    try:
        logger.info(f"eval_ruby called with code length: {len(code)}")
        
        sketchup = get_sketchup_connection()
        
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "eval_ruby",
                "arguments": {
                    "code": code
                }
            },
            request_id=ctx.request_id
        )
        
        logger.info(f"eval_ruby result: {result}")
        
        # Format the response to include the result
        response = {
            "success": True,
            "result": result.get("content", [{"text": "Success"}])[0].get("text", "Success") if isinstance(result.get("content"), list) and len(result.get("content", [])) > 0 else "Success"
        }
        
        return json.dumps(response)
    except Exception as e:
        logger.error(f"Error in eval_ruby: {str(e)}")
        return json.dumps({
            "success": False,
            "error": str(e)
        })

@mcp.tool()
def calculate_distance(
    ctx: Context,
    point1: List[float],
    point2: List[float]
) -> str:
    """Calculate distance between two 3D points"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "calculate_distance",
                "arguments": {
                    "point1": point1,
                    "point2": point2
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error calculating distance: {str(e)}"

@mcp.tool()
def measure_components(
    ctx: Context,
    component_ids: List[str],
    type: str = "center_to_center"
) -> str:
    """Measure distances between components"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "measure_components",
                "arguments": {
                    "component_ids": component_ids,
                    "type": type
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error measuring components: {str(e)}"

@mcp.tool()
def inspect_component(
    ctx: Context,
    component_id: str
) -> str:
    """Get detailed information about a component"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "inspect_component",
                "arguments": {
                    "component_id": component_id
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error inspecting component: {str(e)}"

@mcp.tool()
def create_reference_markers(
    ctx: Context,
    points: List[List[float]],
    size: float = 1.0,
    color: str = "red",
    label_prefix: str = "REF"
) -> str:
    """Create visual reference markers at specified points"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_reference_markers",
                "arguments": {
                    "points": points,
                    "size": size,
                    "color": color,
                    "label_prefix": label_prefix
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error creating reference markers: {str(e)}"

@mcp.tool()
def clear_reference_markers(
    ctx: Context,
    label_prefix: str = "REF"
) -> str:
    """Clear reference markers with specified label prefix"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "clear_reference_markers",
                "arguments": {
                    "label_prefix": label_prefix
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error clearing reference markers: {str(e)}"

@mcp.tool()
def snap_align_component(
    ctx: Context,
    source_component_id: str,
    target_component_id: str,
    alignment_type: str = "center_to_center",
    offset: List[float] = None
) -> str:
    """Snap/align one component to another"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "snap_align_component",
                "arguments": {
                    "source_component_id": source_component_id,
                    "target_component_id": target_component_id,
                    "alignment_type": alignment_type,
                    "offset": offset or [0, 0, 0]
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error snapping/aligning component: {str(e)}"

@mcp.tool()
def create_grid_system(
    ctx: Context,
    origin: List[float] = None,
    x_spacing: float = 10.0,
    y_spacing: float = 10.0,
    x_count: int = 10,
    y_count: int = 10,
    marker_size: float = 0.5,
    show_labels: bool = True,
    color: str = "gray",
    label_prefix: str = "GRID"
) -> str:
    """Create a visual grid reference system"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "create_grid_system",
                "arguments": {
                    "origin": origin or [0, 0, 0],
                    "x_spacing": x_spacing,
                    "y_spacing": y_spacing,
                    "x_count": x_count,
                    "y_count": y_count,
                    "marker_size": marker_size,
                    "show_labels": show_labels,
                    "color": color,
                    "label_prefix": label_prefix
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error creating grid system: {str(e)}"

@mcp.tool()
def query_all_components(
    ctx: Context,
    include_details: bool = True,
    type_filter: str = None
) -> str:
    """Query all components in the model"""
    try:
        sketchup = get_sketchup_connection()
        arguments = {
            "include_details": include_details
        }
        if type_filter:
            arguments["type_filter"] = type_filter
            
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "query_all_components",
                "arguments": arguments
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error querying components: {str(e)}"

@mcp.tool()
def position_relative_to_component(
    ctx: Context,
    source_component_id: str,
    reference_component_id: str,
    relative_position: str,
    offset: List[float] = None
) -> str:
    """Position a component relative to another component"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "position_relative_to_component",
                "arguments": {
                    "source_component_id": source_component_id,
                    "reference_component_id": reference_component_id,
                    "relative_position": relative_position,
                    "offset": offset or [0, 0, 0]
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error positioning component relatively: {str(e)}"

@mcp.tool()
def position_between_components(
    ctx: Context,
    source_component_id: str,
    component1_id: str,
    component2_id: str,
    ratio: float = 0.5,
    offset: List[float] = None
) -> str:
    """Position a component between two other components"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "position_between_components",
                "arguments": {
                    "source_component_id": source_component_id,
                    "component1_id": component1_id,
                    "component2_id": component2_id,
                    "ratio": ratio,
                    "offset": offset or [0, 0, 0]
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error positioning component between others: {str(e)}"

@mcp.tool()
def show_component_bounds(
    ctx: Context,
    component_ids: List[str],
    show_wireframe: bool = True,
    color: str = "yellow",
    label_prefix: str = "BOUNDS"
) -> str:
    """Show bounding boxes for components"""
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "show_component_bounds",
                "arguments": {
                    "component_ids": component_ids,
                    "show_wireframe": show_wireframe,
                    "color": color,
                    "label_prefix": label_prefix
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error showing component bounds: {str(e)}"

@mcp.tool()
def preview_position(
    ctx: Context,
    type: str = "cube",
    position: List[float] = None,
    dimensions: List[float] = None
) -> str:
    """Preview where a component would be positioned without actually creating it
    
    This tool calculates and returns the exact bounds and positioning information
    for a component based on the given parameters, without creating anything in SketchUp.
    
    Position Reference: The 'position' parameter specifies the CENTER POINT of the component.
    The component grows equally in all directions from this center position.
    
    Examples:
    - position: [100, 50, 10], dimensions: [20, 10, 5]
    - Returns bounds from [90, 45, 7.5] to [110, 55, 12.5]
    - Shows center point, corner coordinates, and positioning explanation
    
    Args:
        type: Component type (cube, cylinder, sphere)
        position: [X, Y, Z] coordinates of component CENTER POINT (default: [0,0,0])
        dimensions: [width, height, depth] in SketchUp units (default: [1,1,1])
        
    Returns:
        Detailed positioning preview including bounds, center, corners, and explanation
    """
    try:
        sketchup = get_sketchup_connection()
        result = sketchup.send_command(
            method="tools/call",
            params={
                "name": "preview_position",
                "arguments": {
                    "type": type,
                    "position": position or [0, 0, 0],
                    "dimensions": dimensions or [1, 1, 1]
                }
            },
            request_id=ctx.request_id
        )
        return json.dumps(result)
    except Exception as e:
        return f"Error previewing position: {str(e)}"

def main():
    mcp.run()

if __name__ == "__main__":
    main()