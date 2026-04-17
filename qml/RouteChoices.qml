import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.Configuration 1.0
import "pages"

ApplicationWindow {
    initialPage: Component { FirstPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations


    ConfigurationValue
        {
            id: deviceIdSetting
            key: "/apps/routeChoicesTracker/settings/deviceId"
            defaultValue: ""

        }
}
