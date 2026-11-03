local windowSpeed, springSpeed, mass = 1.5, 1, 1

require("runtime").config("animations.enabled", true)
for name, stiffness in pairs({niriMove = 800, niriWorkspace = 1000}) do
    hl.curve(name, {type = "spring", mass = mass, stiffness = stiffness, dampening = 2 * math.sqrt(mass * stiffness)})
end
hl.curve("niriOpen", {type = "bezier", points = {{0.16, 1}, {0.3, 1}}})
hl.curve("niriClose", {type = "bezier", points = {{1 / 3, 2 / 3}, {2 / 3, 1}}})
hl.animation({leaf = "windowsIn", enabled = true, speed = windowSpeed, bezier = "niriOpen", style = "popin 50%"})
hl.animation({leaf = "windowsOut", enabled = true, speed = windowSpeed, bezier = "niriClose", style = "popin 80%"})
hl.animation({leaf = "windowsMove", enabled = true, speed = springSpeed, spring = "niriMove", style = "slide"})
hl.animation({leaf = "border", enabled = true, speed = windowSpeed, bezier = "niriClose"})
hl.animation({leaf = "borderangle", enabled = false})
hl.animation({leaf = "fade", enabled = true, speed = windowSpeed, bezier = "niriClose"})
hl.animation({leaf = "fadeIn", enabled = true, speed = windowSpeed, bezier = "niriOpen"})
hl.animation({leaf = "fadeOut", enabled = true, speed = windowSpeed, bezier = "niriClose"})
hl.animation({leaf = "layersIn", enabled = false})
hl.animation({leaf = "layersOut", enabled = false})
hl.animation({leaf = "fadeLayersIn", enabled = false})
hl.animation({leaf = "fadeLayersOut", enabled = false})
hl.animation({leaf = "workspaces", enabled = true, speed = springSpeed, spring = "niriWorkspace", style = "slidevert"})
hl.animation({leaf = "specialWorkspace", enabled = true, speed = springSpeed, spring = "niriWorkspace", style = "slidevert"})
require("vars").set("WORKSPACE_SWIPE_AXIS", "vertical")
