import Foundation

/// Ready-to-paste Home Assistant automation for one trigger.
public enum AutomationExample {
    public static let placeholderEntity = "binary_sensor.your_sensor"

    /// `domain.object_id` in lowercase; anything else could break out of the YAML we generate.
    public static func isValidEntityId(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-z0-9_]*\.[a-z0-9][a-z0-9_]*$"#, options: .regularExpression) != nil
    }

    public static func yaml(deviceId: String, source: String, entity: String = placeholderEntity) -> String {
        let entity = isValidEntityId(entity) ? entity : placeholderEntity
        let topics = Topics(deviceId: deviceId)
        let topic = topics.contact(source)
        return """
        alias: Desktop control - \(source)
        description: Sends the state of \(entity) to the macOS app ha-desktop-control.
        mode: queued
        max_exceeded: silent
        triggers:
          - trigger: state
            entity_id: \(entity)
          - trigger: homeassistant
            event: start
          - trigger: mqtt
            topic: homeassistant/status
            payload: online
        actions:
          - choose:
              - conditions:
                  - condition: state
                    entity_id: \(entity)
                    state: "on"
                sequence:
                  - action: mqtt.publish
                    data:
                      topic: \(topic)
                      payload: open
                      retain: true
              - conditions:
                  - condition: state
                    entity_id: \(entity)
                    state: "off"
                sequence:
                  - action: mqtt.publish
                    data:
                      topic: \(topic)
                      payload: closed
                      retain: true

        """
    }
}
