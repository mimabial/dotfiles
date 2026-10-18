import QtQuick
import QtQuick.Layouts
import "../js/Schema.js" as Schema
import "../controls"

Item {
    id: root

    required property var svc
    readonly property var ui: svc ? svc.ui : null
    property bool confirmReset: false
    implicitHeight: rowsCol.implicitHeight + ui.px(12)

    function same(item) {
        return String(svc.cfg[item.key]) === String(svc.defaults[item.key])
    }

    function dimmed(item) {
        return !Schema.applies(item.when, svc.cfg)
    }

    readonly property int changed: {
        var n = 0
        for (var i = 0; i < Schema.items.length; i++)
            if (!same(Schema.items[i])) n++
        return n
    }

    function resetAll() {
        if (!root.confirmReset) { root.confirmReset = true; return }
        root.confirmReset = false
        if (svc && svc.store) svc.store.resetAll(svc.defaults)
    }
    onVisibleChanged: confirmReset = false

    ColumnLayout {
        id: rowsCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: ui.px(16)
        anchors.rightMargin: ui.px(16)
        anchors.topMargin: ui.px(6)
        spacing: 0

        Repeater {
            model: Schema.items
            delegate: ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    visible: index > 0
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: ui.tint(0.07)
                }
                SettingRow {
                    Layout.fillWidth: true
                    Layout.topMargin: ui.px(14)
                    Layout.bottomMargin: ui.px(14)
                    ui: root.ui
                    settingKey: modelData.key
                    label: modelData.label
                    hint: modelData.hint || ""
                    kind: modelData.kind
                    control: modelData.control || ""
                    options: modelData.options || []
                    labels: modelData.labels || ({})
                    defaultValue: root.svc.defaults[modelData.key]
                    dimmed: root.dimmed(modelData)
                    value: root.svc.cfg[modelData.key]
                    onEdited: function(v) { if (root.svc) root.svc.setValue(modelData.key, v) }
                }
            }
        }
    }
}
