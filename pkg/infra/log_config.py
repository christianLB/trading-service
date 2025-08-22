"""Log configuration with rotation support."""
import logging
import logging.handlers
import os
from pathlib import Path
from typing import Optional

import structlog
from structlog.stdlib import LoggerFactory

from pkg.infra.settings import get_settings


def setup_logging(
    log_level: str = "INFO",
    log_dir: Optional[str] = None,
    enable_rotation: bool = True,
    max_bytes: int = 10 * 1024 * 1024,  # 10MB
    backup_count: int = 7,  # Keep 7 days of logs
) -> None:
    """
    Configure structured logging with rotation.
    
    Args:
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR)
        log_dir: Directory for log files (None for console only)
        enable_rotation: Enable log rotation
        max_bytes: Maximum size of each log file
        backup_count: Number of backup files to keep
    """
    settings = get_settings()
    
    # Create log directory if specified
    if log_dir:
        Path(log_dir).mkdir(parents=True, exist_ok=True)
    
    # Configure Python's logging
    handlers = []
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, log_level))
    handlers.append(console_handler)
    
    # File handler with rotation
    if log_dir:
        log_file = os.path.join(log_dir, f"{settings.app_name}.log")
        
        if enable_rotation:
            # Rotating file handler
            file_handler = logging.handlers.RotatingFileHandler(
                filename=log_file,
                maxBytes=max_bytes,
                backupCount=backup_count,
                encoding="utf-8",
            )
        else:
            # Simple file handler
            file_handler = logging.FileHandler(
                filename=log_file,
                encoding="utf-8",
            )
        
        file_handler.setLevel(getattr(logging, log_level))
        handlers.append(file_handler)
    
    # Configure root logger
    logging.basicConfig(
        level=getattr(logging, log_level),
        handlers=handlers,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    
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
            structlog.processors.CallsiteParameterAdder(
                parameters=[
                    structlog.processors.CallsiteParameter.FILENAME,
                    structlog.processors.CallsiteParameter.LINENO,
                    structlog.processors.CallsiteParameter.FUNC_NAME,
                ]
            ),
            structlog.dev.ConsoleRenderer() if settings.app_env == "dev" else structlog.processors.JSONRenderer(),
        ],
        context_class=dict,
        logger_factory=LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_correlation_id() -> str:
    """Generate a correlation ID for request tracking."""
    import uuid
    return str(uuid.uuid4())


def add_correlation_id(logger, method_name, event_dict):
    """Add correlation ID to log entries."""
    if "correlation_id" not in event_dict:
        event_dict["correlation_id"] = get_correlation_id()
    return event_dict


class LogRotationManager:
    """Manage log rotation and cleanup."""
    
    def __init__(self, log_dir: str, retention_days: int = 7):
        self.log_dir = Path(log_dir)
        self.retention_days = retention_days
    
    def compress_old_logs(self) -> int:
        """Compress logs older than 1 day."""
        import gzip
        import shutil
        from datetime import datetime, timedelta
        
        compressed_count = 0
        cutoff_time = datetime.now() - timedelta(days=1)
        
        for log_file in self.log_dir.glob("*.log"):
            # Skip already compressed files
            if log_file.suffix == ".gz":
                continue
            
            # Check file age
            mtime = datetime.fromtimestamp(log_file.stat().st_mtime)
            if mtime < cutoff_time:
                # Compress the file
                gz_file = log_file.with_suffix(".log.gz")
                with open(log_file, "rb") as f_in:
                    with gzip.open(gz_file, "wb") as f_out:
                        shutil.copyfileobj(f_in, f_out)
                
                # Remove original file
                log_file.unlink()
                compressed_count += 1
        
        return compressed_count
    
    def cleanup_old_logs(self) -> int:
        """Delete logs older than retention period."""
        from datetime import datetime, timedelta
        
        deleted_count = 0
        cutoff_time = datetime.now() - timedelta(days=self.retention_days)
        
        for log_file in self.log_dir.glob("*.log*"):
            mtime = datetime.fromtimestamp(log_file.stat().st_mtime)
            if mtime < cutoff_time:
                log_file.unlink()
                deleted_count += 1
        
        return deleted_count
    
    def run_maintenance(self) -> dict:
        """Run log maintenance tasks."""
        results = {
            "compressed": self.compress_old_logs(),
            "deleted": self.cleanup_old_logs(),
        }
        return results