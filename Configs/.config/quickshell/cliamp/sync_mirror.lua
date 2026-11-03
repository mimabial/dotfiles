local options = {cliamp_ctl = "", last_started = ""}
require("mp.options").read_options(options)

mp.register_event("start-file", function(event)
    local record = io.open(options.last_started, "w")
    record:write(event.playlist_entry_id)
    record:close()
    mp.commandv("run", "python3", options.cliamp_ctl, "sync")
end)
