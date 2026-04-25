# Backend Request/Response Logging

This logging system captures all incoming requests and outgoing responses from Godot to help you debug optimization issues.

## Features

- **Automatic Request/Response Logging**: All HTTP requests and responses are automatically logged
- **Structured Logging**: Uses `structlog` for machine-readable JSON logs
- **Performance Metrics**: Tracks response time and response size for each request
- **Error Tracking**: Captures and logs any errors that occur
- **Multiple Log Formats**: Logs stored in both structured format and JSONL files for easy analysis

## How It Works

### 1. Enable Logging

The logging is automatically enabled when you start the backend. The middleware in `main.py` logs all requests and responses.

### 2. Log Files

Logs are stored in the `logs/` directory:

- **`app.log`**: Main application log (timestamped, human-readable)
- **`requests.jsonl`**: All incoming requests (JSON Lines format)
- **`responses.jsonl`**: All outgoing responses (JSON Lines format)
- **`errors.jsonl`**: All errors that occurred (JSON Lines format)

### 3. What Gets Logged

#### For Each Request:
```json
{
  "timestamp": "2025-04-25T12:00:00.123456",
  "request_id": "unique_id",
  "method": "POST",
  "path": "/solve/full",
  "query_params": {},
  "client": "127.0.0.1",
  "headers": { ... },
  "body": { ... }  // Full request payload
}
```

#### For Each Response:
```json
{
  "timestamp": "2025-04-25T12:00:00.125000",
  "request_id": "unique_id",
  "method": "POST",
  "path": "/solve/full",
  "status_code": 200,
  "response_time_ms": 15.2,
  "response_size_bytes": 4526,
  "body": { ... }  // Full response payload
}
```

## Analyzing Logs

### Using the Log Analyzer Script

The `analyze_logs.py` script provides easy analysis of your logs:

```bash
# Get overall statistics
python analyze_logs.py

# View a specific request-response pair
python analyze_logs.py --pair <request_id>
```

### Analysis Output

The analyzer provides:

1. **Request Statistics**
   - Total number of requests
   - Endpoints called
   - HTTP methods used
   - Last 5 requests

2. **Response Statistics**
   - Status code distribution
   - Average response time per status
   - Average response size per status
   - Top 5 slowest responses
   - Top 5 fastest responses

3. **Error Analysis**
   - Error types
   - Error frequency
   - Recent errors

### Manual Analysis

Since logs are in JSONL format (one JSON object per line), you can easily process them:

```bash
# View all requests to /solve/full
grep "/solve/full" logs/requests.jsonl | jq .

# View response times for all requests
cat logs/responses.jsonl | jq '{path: .path, time: .response_time_ms, status: .status_code}'

# Find slow responses (> 100ms)
cat logs/responses.jsonl | jq 'select(.response_time_ms > 100)'
```

## Debugging Godot Integration Issues

### Step 1: Run Your Game

Start the backend and run your Godot game:

```bash
# Terminal 1: Start backend
cd backend
python -m uvicorn main:app --reload

# Terminal 2: Run Godot game (in separate terminal)
```

### Step 2: Reproduce the Issue

Play through the game and reproduce the issue you want to debug.

### Step 3: Analyze Logs

```bash
# Get overview of what happened
python analyze_logs.py

# Look at specific request-response pairs
python analyze_logs.py --pair <request_id_from_logs>
```

### Step 4: Examine Data Flow

Check the request bodies to see what Godot is sending:

```bash
# See recent requests with their bodies
tail -20 logs/requests.jsonl | jq '{endpoint: .path, method: .method, body: .body}'

# See responses from specific endpoint
grep "/solve/full" logs/responses.jsonl | tail -5 | jq .body
```

## Common Issues to Look For

1. **Missing Data**: Check if Godot is sending all required fields in requests
2. **Type Mismatches**: Look for fields that don't match expected types
3. **Performance Issues**: Use `response_time_ms` to identify slow endpoints
4. **Partial Responses**: Check if responses are being truncated or incomplete
5. **Error Responses**: Check for 400, 422, 500 status codes in `responses.jsonl`

## Disabling Logging

To disable the request/response logging (e.g., in production):

1. Comment out or remove this line from `main.py`:
   ```python
   app.add_middleware(RequestResponseLogger)
   ```

2. Or modify `logging_service.py` to skip logging certain endpoints

## Log Rotation

Currently, logs append infinitely. For production, consider adding log rotation:

```python
# In logging_service.py, use RotatingFileHandler
from logging.handlers import RotatingFileHandler

handler = RotatingFileHandler(
    LOGS_DIR / "app.log",
    maxBytes=10_000_000,  # 10 MB
    backupCount=5
)
```

## Performance Impact

The logging system is designed to have minimal performance impact:
- Logs are written asynchronously
- Logging occurs after response processing
- Response time measurement doesn't include logging overhead

If you notice performance issues, check the `response_time_ms` values - the logging itself shouldn't add more than 1-2ms.
