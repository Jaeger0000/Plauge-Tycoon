import json
import logging
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import structlog
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

# Create logs directory if it doesn't exist
LOGS_DIR = Path("logs")
LOGS_DIR.mkdir(exist_ok=True)

# Configure structlog
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer(),
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

# Set up standard logging
logging.basicConfig(
    format="%(message)s",
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOGS_DIR / "app.log"),
        logging.StreamHandler(),
    ],
)

logger = structlog.get_logger()


class RequestResponseLogger(BaseHTTPMiddleware):
    """
    Middleware to log all incoming requests and outgoing responses.
    Saves detailed logs to JSON files for debugging.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        # Record start time
        start_time = time.time()
        
        # Get request details
        request_id = f"{datetime.now().timestamp()}"
        method = request.method
        path = request.url.path
        query_params = dict(request.query_params)
        
        # Read request body (we need to do this carefully to not break the request)
        body = b""
        if method in ["POST", "PUT", "PATCH"]:
            try:
                body = await request.body()
            except Exception as e:
                logger.warning(f"Failed to read request body: {e}")
        
        # Parse body as JSON if possible
        request_body = None
        if body:
            try:
                request_body = json.loads(body.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                request_body = {"error": "Could not parse body as JSON"}
        
        # Create a new receive function that returns the cached body
        async def receive():
            return {"type": "http.request", "body": body}
        
        request._receive = receive
        
        # Log incoming request
        log_entry = {
            "timestamp": datetime.now().isoformat(),
            "request_id": request_id,
            "type": "REQUEST",
            "method": method,
            "path": path,
            "query_params": query_params if query_params else None,
            "client": request.client.host if request.client else None,
            "headers": dict(request.headers),
            "body": request_body,
        }
        
        logger.info("incoming_request", **log_entry)
        
        # Call the next middleware/route
        try:
            response = await call_next(request)
            status_code = response.status_code
        except Exception as e:
            # Log the exception
            logger.error("request_failed", error=str(e), request_id=request_id)
            raise
        
        # Calculate response time
        process_time = time.time() - start_time
        
        # Read response body
        response_body = b""
        async for chunk in response.body_iterator:
            response_body += chunk
        
        # Parse response body as JSON if possible
        response_data = None
        if response_body:
            try:
                response_data = json.loads(response_body.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                response_data = {"error": "Could not parse response body as JSON"}
        
        # Log response
        response_log_entry = {
            "timestamp": datetime.now().isoformat(),
            "request_id": request_id,
            "type": "RESPONSE",
            "method": method,
            "path": path,
            "status_code": status_code,
            "response_time_ms": round(process_time * 1000, 2),
            "response_size_bytes": len(response_body),
            "body": response_data,
        }
        
        logger.info("outgoing_response", **response_log_entry)
        
        # Create a new response with the cached body
        from starlette.responses import Response as StarletteResponse
        new_response = StarletteResponse(
            content=response_body,
            status_code=response.status_code,
            headers=dict(response.headers),
            media_type=response.media_type,
        )
        return new_response


class JSONFileLogger:
    """
    Logger that saves requests and responses to separate JSON files for easy analysis.
    """
    
    def __init__(self, log_dir: Path = LOGS_DIR):
        self.log_dir = log_dir
        self.log_dir.mkdir(exist_ok=True)
        self.requests_file = self.log_dir / "requests.jsonl"
        self.responses_file = self.log_dir / "responses.jsonl"
        self.errors_file = self.log_dir / "errors.jsonl"
    
    def log_request(
        self,
        request_id: str,
        method: str,
        path: str,
        body: Any = None,
        headers: dict = None,
        query_params: dict = None,
        client_ip: str = None,
    ) -> None:
        """Log an incoming request."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "request_id": request_id,
            "method": method,
            "path": path,
            "client_ip": client_ip,
            "query_params": query_params,
            "headers": headers,
            "body": body,
        }
        self._write_jsonl(self.requests_file, entry)
    
    def log_response(
        self,
        request_id: str,
        method: str,
        path: str,
        status_code: int,
        body: Any = None,
        response_time_ms: float = 0.0,
        response_size_bytes: int = 0,
    ) -> None:
        """Log an outgoing response."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "request_id": request_id,
            "method": method,
            "path": path,
            "status_code": status_code,
            "response_time_ms": response_time_ms,
            "response_size_bytes": response_size_bytes,
            "body": body,
        }
        self._write_jsonl(self.responses_file, entry)
    
    def log_error(
        self,
        request_id: str,
        path: str,
        method: str,
        error_message: str,
        error_type: str = "unknown",
    ) -> None:
        """Log an error."""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "request_id": request_id,
            "method": method,
            "path": path,
            "error_type": error_type,
            "error_message": error_message,
        }
        self._write_jsonl(self.errors_file, entry)
    
    @staticmethod
    def _write_jsonl(file_path: Path, entry: dict) -> None:
        """Write a single entry to a JSONL file."""
        try:
            with open(file_path, "a") as f:
                f.write(json.dumps(entry) + "\n")
        except Exception as e:
            logger.error(f"Failed to write log entry to {file_path}: {e}")


# Global logger instance
json_file_logger = JSONFileLogger()


def get_logger():
    """Get the structlog logger instance."""
    return logger


def get_json_file_logger():
    """Get the JSON file logger instance."""
    return json_file_logger
