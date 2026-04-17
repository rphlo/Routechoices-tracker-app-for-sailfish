import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    Label {
        id: label
        anchors.centerIn: parent
        text: qsTr("Routechoices app")
    }
    Image {
        id: appImage
        source: "../pages/RouteChoices.png"
        anchors.fill: parent
    }
    CoverActionList {
        id: coverAction 
    }
}
