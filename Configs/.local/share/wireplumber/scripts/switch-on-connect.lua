local cutils = require("common-utils")

SimpleEventHook {
  name = "custom/switch-on-connect",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink", type = "pw-global" },
      Constraint { "device.bus", "=", "usb", type = "pw" },
    },
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink", type = "pw-global" },
      Constraint { "device.api", "=", "bluez5", type = "pw" },
    },
  },
  execute = function (event)
    local default_metadata = cutils.get_default_metadata_object ()
    default_metadata:set (0, "default.configured.audio.sink", "Spa:String:JSON",
        Json.Object { name = event:get_subject ().properties ["node.name"] }:to_string ())
  end
}:register ()
