pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var consumers: []
    readonly property var profiles: Array.from(new Set(consumers.map(consumer => consumer.profile)))
    readonly property var modes: ["bars", "foobar", "dots", "wave", "mirror", "blocks"]
    readonly property int maxValue: 1000
    property var values: ({})

    function clear(profile) {
        const frames = Object.assign({}, values)
        delete frames[profile]
        values = frames
    }

    Variants {
        model: root.profiles
        delegate: Process {
            id: process
            required property string modelData
            readonly property var settings: JSON.parse(modelData)
            readonly property string config: "[general]\nbars = " + settings.bars + "\nframerate = " + settings.fps + "\nsleep_timer = 1"
                + "\n[output]\nmethod = raw\nchannels = mono\nmono_option = average\nraw_target = /dev/stdout"
                + "\ndata_format = ascii\nascii_max_range = " + root.maxValue + "\nbar_delimiter = 59\nframe_delimiter = 10\n"
                + "[smoothing]\nnoise_reduction = " + settings.smoothing + "\n"
            command: ["cava", "-p", "/dev/stdin"]
            running: root.consumers.some(consumer => consumer.profile === process.modelData && consumer.visible && consumer.playing)
            stdinEnabled: true
            onStarted: { process.write(process.config); process.stdinEnabled = false }
            onRunningChanged: if (!process.running) { process.stdinEnabled = true; root.clear(process.modelData) }
            Component.onDestruction: root.clear(process.modelData)
            stdout: SplitParser {
                onRead: line => root.values = Object.assign({}, root.values, {
                    [process.modelData]: line.slice(0, -1).split(";").map(value => Number(value) / root.maxValue)
                })
            }
        }
    }
}
