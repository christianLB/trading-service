import hashlib
import hmac
import json
from datetime import datetime
from typing import Any, Dict

import httpx

from pkg.infra.logging import get_logger
from pkg.infra.settings import get_settings

logger = get_logger(__name__)


async def send_webhook(event_type: str, data: Dict[str, Any]):
    settings = get_settings()
    
    if not settings.webhook_url:
        logger.debug("Webhook URL not configured, skipping", event=event_type)
        return
    
    payload = {
        "event": event_type,
        "ts": datetime.utcnow().isoformat() + "Z",
        **data,
    }
    
    body = json.dumps(payload)
    signature = hmac.new(
        settings.webhook_secret.encode(),
        body.encode(),
        hashlib.sha256,
    ).hexdigest()
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                settings.webhook_url,
                content=body,
                headers={
                    "Content-Type": "application/json",
                    "X-Signature": signature,
                },
                timeout=5.0,
            )
            
            if response.is_error:
                logger.warning(
                    "Webhook failed",
                    event=event_type,
                    status_code=response.status_code,
                    response=response.text,
                )
            else:
                logger.info("Webhook sent", event=event_type, status_code=response.status_code)
    
    except Exception as e:
        logger.error("Webhook error", event=event_type, error=str(e))