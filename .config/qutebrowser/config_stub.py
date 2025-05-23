# config_stub.py - Stubs for qutebrowser config development
# This provides better autocomplete in your editor


class ConfigStub:
    """Stub for config object"""

    def load_autoconfig(self, value=True):
        pass

    def bind(self, key, command, mode="normal"):
        pass

    def unbind(self, key, mode="normal"):
        pass

    def set(self, option, value, pattern=None):
        pass

    def get(self, option, pattern=None):
        pass


class ConfigContainerStub:
    """Stub for c object with all config options"""

    def __setattr__(self, name, value):
        pass

    def __getattr__(self, name):
        # Return self for chaining (c.content.blocking.enabled)
        return self


# Create stub instances
config = ConfigStub()
c = ConfigContainerStub()
