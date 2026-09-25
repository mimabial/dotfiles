pragma ComponentBehavior: Bound

import QtQuick
import qs as ShellUi
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var service: null
  property var host: null
  property var settings: ({})
  property string temperatureUnit: "Celsius"
  property bool publicIpEnabled: true
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family

  readonly property var events: service ? service.alertEvents : []

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(10)

  Card {
    foreground: root.foreground

    SectionTitle { text: "Watch"; fontFamily: root.fontFamily }

    Text {
      width: parent.width
      text: "Alerts are off until enabled here. A reading must reach its limit for three samples before a notification is sent."
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: Model.ALERTS.length

      delegate: Column {
        id: alertRow
        required property int index
        readonly property var def: Model.ALERTS[index]
        readonly property bool armed: !!root.service && root.service.alertEnabled(def.id)
        readonly property var reading: root.service ? root.service.alertValue(root.service.snapshot, def.id) : null

        width: parent.width
        spacing: Style.space(3)

        Item {
          width: parent.width
          height: Style.space(28)

          ShellUi.ToggleSwitch {
            id: alertSwitch
            shell: root.host ? root.host.shell : null
            checked: alertRow.armed
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            onToggled: if (root.service) root.service.setAlertEnabled(alertRow.def.id, !alertRow.armed)
          }

          Text {
            anchors.left: alertSwitch.right
            anchors.leftMargin: Style.space(12)
            anchors.right: liveReading.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: alertRow.def.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.foreground
            opacity: alertRow.armed ? 1 : 0.65
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: alertRow.armed
          }

          Text {
            id: liveReading
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: alertRow.def.id === "driveHealth" ? "SMART" : isFinite(alertRow.reading) && alertRow.reading !== null
              ? Math.round(alertRow.reading) + alertRow.def.unit : "—"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          visible: alertRow.def.threshold !== undefined
          x: alertSwitch.width + Style.space(12)
          spacing: Style.space(5)

          Text {
            text: "Limit"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            height: Style.space(22)
            verticalAlignment: Text.AlignVCenter
          }

          PanelActionButton {
            iconText: "−"
            foreground: root.foreground
            fontFamily: root.fontFamily
            size: Style.space(22)
            enabled: root.service && root.service.alertThreshold(alertRow.def.id) > alertRow.def.min
            onClicked: root.service.setAlertThreshold(alertRow.def.id, root.service.alertThreshold(alertRow.def.id) - alertRow.def.step)
          }

          Text {
            text: root.service ? root.service.alertThreshold(alertRow.def.id) + alertRow.def.unit : ""
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            height: Style.space(22)
            verticalAlignment: Text.AlignVCenter
          }

          PanelActionButton {
            iconText: "+"
            foreground: root.foreground
            fontFamily: root.fontFamily
            size: Style.space(22)
            enabled: root.service && root.service.alertThreshold(alertRow.def.id) < alertRow.def.max
            onClicked: root.service.setAlertThreshold(alertRow.def.id, root.service.alertThreshold(alertRow.def.id) + alertRow.def.step)
          }
        }

        Text {
          visible: alertRow.def.id === "driveHealth"
          x: alertSwitch.width + Style.space(12)
          width: parent.width - x
          text: "Checks connected drives every five minutes; warns on bad sectors or SMART failure."
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Card {
    foreground: root.foreground

    Item {
      width: parent.width
      height: Style.space(24)

      SectionTitle { text: "Recent alerts"; fontFamily: root.fontFamily; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }
      PanelActionButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰃢"
        tooltipText: "Clear alert history"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.service && root.events.length > 0
        onClicked: root.service.clearAlertEvents()
      }
    }

    Text {
      visible: root.events.length === 0
      text: "No alerts recorded. The latest 20 events are kept across shell restarts."
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.events.length

      delegate: Column {
        id: eventRow
        required property int index
        property bool expanded: false
        readonly property var event: root.events[index] || ({})

        width: parent.width
        spacing: Style.space(3)

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.right: when.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: eventRow.event.title || "Alert"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            id: when
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: eventRow.event.at ? new Date(eventRow.event.at).toLocaleString() : ""
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: eventRow.expanded = !eventRow.expanded
          }
        }

        Text {
          width: parent.width
          text: eventRow.event.message || ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: eventRow.expanded
          width: parent.width
          text: Array.isArray(eventRow.event.context) ? eventRow.event.context.join(" · ") : ""
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
