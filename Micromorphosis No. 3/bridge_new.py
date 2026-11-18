import asyncio
import websockets
from pythonosc import dispatcher, osc_server

# Store connected browser clients
CLIENTS = set()

def data_handler(address, *args):
    """Handles the numerical particle data."""
    if CLIENTS:
        message = ",".join(map(str, args))
        asyncio.run_coroutine_threadsafe(broadcast(message), loop)

def log_handler(address, *args):
    """Handles the text log data from SuperCollider."""
    if CLIENTS:
        # Prepend 'LOG:' so the HTML/JS knows to route this to the text box
        message = "LOG:" + str(args[0])
        asyncio.run_coroutine_threadsafe(broadcast(message), loop)

async def broadcast(message):
    """Broadcasts to all connected clients and handles disconnects."""
    if not CLIENTS:
        return
    
    # Create a list of send tasks
    storage = [client.send(message) for client in CLIENTS]
    if storage:
        # Wait for all sends to finish, ignore errors if a client closed
        await asyncio.gather(*storage, return_exceptions=True)

async def ws_handler(websocket):
    """Handles browser connection."""
    print(f"Browser connected.")
    CLIENTS.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        CLIENTS.remove(websocket)
        print("Browser disconnected.")

async def main():
    global loop
    loop = asyncio.get_running_loop()
    
    # OSC Server Setup
    disp = dispatcher.Dispatcher()
    # Map the particle data
    disp.map("/vaziri/data", data_handler)
    # Map the text log data
    disp.map("/vaziri/log", log_handler)
    
    # Listen to SuperCollider on port 12345
    server = osc_server.AsyncIOOSCUDPServer(("127.0.0.1", 12345), disp, loop)
    transport, protocol = await server.create_serve_endpoint()
    
    # WebSocket Server Setup on port 8080
    async with websockets.serve(ws_handler, "localhost", 8080):
        print("Bridge Active: SC (12345) -> Browser (8080)")
        await asyncio.Future() 

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nBridge stopped by user.")