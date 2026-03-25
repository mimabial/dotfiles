import logging
import os


LOGGER_NAME = "hypr"
HANDLER_MARKER = "_hypr_logger_handler"


def _get_noop_logger():
    logger = logging.getLogger(f"{LOGGER_NAME}.noop")
    logger.propagate = False
    logger.setLevel(logging.CRITICAL + 1)

    if not logger.handlers:
        logger.addHandler(logging.NullHandler())

    return logger


def get_logger():
    """Return a stdlib logger configured from LOG_LEVEL."""
    log_level = os.getenv("LOG_LEVEL")
    if not log_level:
        return _get_noop_logger()

    level = getattr(logging, log_level.upper(), logging.INFO)
    logger = logging.getLogger(LOGGER_NAME)
    logger.propagate = False
    logger.setLevel(level)

    handler = next((item for item in logger.handlers if getattr(item, HANDLER_MARKER, False)), None)
    if handler is None:
        handler = logging.StreamHandler()
        setattr(handler, HANDLER_MARKER, True)
        logger.addHandler(handler)

    handler.setLevel(level)
    return logger
