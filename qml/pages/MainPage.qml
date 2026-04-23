// Main View

import QtQuick 2.0
import Sailfish.Silica 1.0
import QtPositioning 5.4
import Nemo.Configuration 1.0
import org.nemomobile.systemsettings 1.0

Page {
    id: mainPage
    allowedOrientations: Orientation.Portrait
    readonly property string postSecret : "<apikeyhere>";
    property string deviceId: "";
    readonly property string baseUrl : "https://api.routechoices.com";
    property var coordinateBuffer: [];
    property int lastBatteryLevel : 0;
    property int lastBatteryCheckTS: 0;
    property BatteryStatus batteryInfo: BatteryStatus {}
    readonly property int maxTimeDiff: 60 * 60;
    readonly property int positioningUpdateInterval: 1 * 1000;
    readonly property int postCoordinatesInterval: 5 * 1000;

    // Add an Image as the background
    Image {
        source: "banner.png"
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
    }
    // Title header, for now
    TextField {
        id: header
        placeholderText: qsTr("Routechoices Tracker")
        width: parent.width * 0.8
        horizontalAlignment: TextInput.AlignHCenter // Align text to the center
        anchors {
            topMargin:200
            horizontalCenter: appImage.horizontalCenter
        }
    }
    // Satellite icon to show user when positioning is providing valid coordinates.
    Icon {
        id: gpsImage
        source: "image://theme/icon-m-gps"
        visible: false
        anchors.top: header.bottom
        horizontalAlignment: TextInput.AlignHCenter // Align  to the center
    }
    // Internet icon to show when connection to server exists.
    Icon {
        id: connectionIcon
        source: "image://theme/icon-m-website"
        visible: false
        anchors.top: gpsImage.bottom
        horizontalAlignment: TextInput.AlignHCenter // Align  to the center
    }
    // RC logo pic
    Image {
        id: appImage
        source: "RouteChoices.png"
        anchors.centerIn: parent
        anchors.top: gpsImage.bottom
    }

    // Button to get start the GPS tracking and send to server
    Button {
        id: startButton
        text: qsTr("Start Tracking")
        onClicked: {
            startStopTracking();
        }
        enabled: false
        anchors {
            top: appImage.bottom
            horizontalCenter: coordinatesText.horizontalCenter
        }
        border.color: "#EEEEEE"
        color: "#3498db"
    }

    // Text box to display GPS coordinates. Should hide in non debug versions?
    TextField {
        id: coordinatesText
        placeholderText: qsTr("GPS Coordinates will appear here")
        anchors {
            bottom: deviceIdText.top
            horizontalCenter: appImage.horizontalCenter
        }
        visible: false
    }

    // Text box to display DevID
    TextField {
        id: deviceIdText
        placeholderText: qsTr("Initializing, please wait")
        anchors {
            bottom: parent.bottom
            horizontalCenter: appImage.horizontalCenter
        }
        width: parent.width * 0.8 // Set the width based on your design
        horizontalAlignment: TextInput.AlignHCenter // Align text to the center
    }

    // column would end here
    Component.onCompleted: {
        coordinatesText.visible = true;
        checkServerTime();
    }

    function checkServerTime() {
        // Create XmlHttpRequest
        var xhr = new XMLHttpRequest();

        // Setup the request
        xhr.open("GET", baseUrl + "/time/", true);
        xhr.setRequestHeader("Content-Type", "application/json");

        // Handle the response
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    connectionIcon.visible = true;
                    // Parse the JSON response
                    var jsonResponse = JSON.parse(xhr.responseText);

                    // Access the 'time' property from the JSON response
                    var serverTime = jsonResponse.time;
                    var localTime = new Date().getTime() / 1000;

                    console.log("SERVER TIME:", serverTime);
                    console.log("DEVICE TIME:", localTime.toString());
                    var timeDiff = Math.abs(serverTime - localTime);
                    if (timeDiff <= maxTimeDiff){
                        requestDeviceId();
                        startButton.enabled = true;
                    } else {
                        coordinatesText.text = "Check device clock!";
                    }
                } else {
                    coordinatesText.text = "Failed to fetch server time " + xhr.status.toString();
                    console.error("HTTP request failed with status:", xhr.status, xhr.statusText);
                    connectionIcon.visible = false;
                }
            }
        };
        // Send the request
        xhr.send();
    }

    function updateBatteryLevel() {
        var timeSinceLastUpdate = +(new Date()) / 1000 - lastBatteryCheckTS;
        if (timeSinceLastUpdate < 60) {
            return;
        }
    
        if (batteryInfo && batteryInfo.chargePercentage && batteryInfo.chargePercentage >= 0) {
            lastBatteryCheckTS = +(new Date()) / 1000;
            lastBatteryLevel = batteryInfo.chargePercentage;
            console.log("BAT: " + batteryInfo.chargePercentage);
        } else {
            lastBatteryLevel = null;
        }
    }

    function startStopTracking() {
        positionUploadTimer.running = !positionUploadTimer.running;
        if (positionUploadTimer.running) {
            startButton.text = "Stop tracking"
            positionUpdater.start();
        } else {
            startButton.text = "Start tracking"
            positionUpdater.stop();
        }
    }

    function requestDeviceId() {
        deviceId = deviceIdSetting.value;

        // request new devId only if we did not have it in the settings
        if (!deviceId || deviceId.length === 0) {
            var request = new XMLHttpRequest();
            
            request.open("POST", baseUrl + "/device/", true);
            request.setRequestHeader("Content-Type", "application/json");
            request.setRequestHeader("Authorization", "Bearer " + postSecret);

            request.onreadystatechange = function() {
                if (request.readyState === XMLHttpRequest.DONE) {
                    if (request.status === 200 || request.status === 201) {
                        // Parse the JSON response
                        var data = JSON.parse(request.responseText);
                        deviceId = data.device_id;
                    } else {
                        header.text = "Error sending POST request " + request.status.toString();
                    }
                    if (!deviceId  || deviceId.length === 0) {
                        requestDeviceId();
                        return;
                    }
                    deviceIdText.text = "Device ID: " + deviceId;
                    deviceIdSetting.value = deviceId;
                }
            };

            request.send("{}");
        } else {
            deviceIdText.text = "Device ID: " + deviceId;
        }
    }

    // Function to send GPS coordinates with POST request
    function sendLocationCoordinates() {
        console.log("coordinateBuffer length: " + coordinateBuffer.length);
        if (coordinateBuffer.length === 0) {
            return;
        }
        var latitudes = "";
        var longitudes = "";
        var timeStamps = "";
        
        var bufferSize = coordinateBuffer.length;
        for (var i = 0; i < bufferSize; i++) {
            var coordinates = coordinateBuffer[i];
            latitudes += coordinates.latitude.toString() + ",";
            longitudes += coordinates.longitude.toString() + ",";
            timeStamps += Math.round(coordinates.timestamp).toString() + ",";
        }

        var data = {
            "device_id": deviceId,
            "latitudes": latitudes,
            "longitudes": longitudes,
            "timestamps": timeStamps,
        };

        updateBatteryLevel();
        if (lastBatteryLevel !== null && lastBatteryLevel >= 0 && lastBatteryLevel <= 100) {
            data.battery = lastBatteryLevel.toString();
        }

        // Create HTTP request
        var request = new XMLHttpRequest();
        request.open("POST", baseUrl + "/locations/", true);
        request.setRequestHeader("Content-Type", "application/json");
        request.setRequestHeader("Authorization", "Bearer " + postSecret);

        // Handle response
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE) {
                if (request.status === 200 || request.status === 201) {
                    console.log("POST request successful");
                    coordinateBuffer.splice(0, bufferSize);
                } else {
                    header.text = "POST error: " + request.status.toString();
                    console.log("err: " + request.statusText);
                }
            }
        };
        // Send the request with JSON data
        request.send(JSON.stringify(data));
    }

    // Timer to send coordinates upon firing
    Timer {
        id: positionUploadTimer
        interval: postCoordinatesInterval
        running: false
        repeat: true
        onTriggered: {
            sendLocationCoordinates();
        }
    }
    
    PositionSource {
        id: positionUpdater
        updateInterval: positioningUpdateInterval
        active: true
        onSourceErrorChanged: {
            if (positionUpdater.sourceError !== PositionSource.NoError) {
                coordinatesText.text = "LocationError: " + positionUpdater.sourceError;
            }
        }
        onPositionChanged: {
            var positionSource = positionUpdater;
            if (positionSource.sourceError === PositionSource.NoError && positionSource.position.latitudeValid && positionSource.position.longitudeValid ) {
                var timestamp = new Date().getTime() / 1000;
                var latitude = positionSource.position.coordinate.latitude;
                var longitude = positionSource.position.coordinate.longitude;
                gpsImage.visible = true;
                
                coordinatesText.text = "LatLon: " + latitude.toFixed(5).toString() + ", " + longitude.toFixed(5).toString() +
                        (lastBatteryLevel !== null ? ("\nBat: " + lastBatteryLevel) : "") +
                        "\nTS: " + timestamp;

                coordinateBuffer.push({
                    "latitude": latitude,
                    "longitude": longitude,
                    "timestamp": timestamp
                });
            } else {
                gpsImage.visible = false;
            }
        }
    }
}
