import SwiftUI
import PlaygroundSupport

// Playground for https://movingparts.io/styling-components-in-swiftui

struct MySlider<Label: View, ValueLabel: View>: View {
    @Binding
    var value: Double

    var bounds: ClosedRange<Double>

    var label: Label

    var minimumValueLabel: ValueLabel

    var maximumValueLabel: ValueLabel

    var onEditingChanged: (Bool) -> Void

    @Environment(\.mySliderStyle)
    var style

    init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> Label,
        minimumValueLabel: () -> ValueLabel,
        maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.bounds = bounds
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        let configuration = MySliderStyleConfiguration(
            value: $value,
            bounds: bounds,
            label: label,
            minimumValueLabel: minimumValueLabel,
            maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged
        )

        AnyView(style.resolve(configuration: configuration))
            .accessibilityElement(children: .combine)
            .accessibilityValue(valueText)
            .accessibilityAdjustableAction { direction in
                let boundsLength = bounds.upperBound - bounds.lowerBound
                let step = boundsLength / 10
                switch direction {
                case .increment:
                    value = max(value + step, bounds.lowerBound)
                case .decrement:
                    value = max(value - step, bounds.lowerBound)
                @unknown default:
                    break
                }
            }
    }

    var valueText: Text {
         if bounds == 0.0...1.0 {
             return Text(value, format: .percent)
         } else {
             return Text(value, format: .number)
         }
    }
}

// MARK: - Style Configuration Initializer

extension MySlider where Label == MySliderStyleConfiguration.Label, ValueLabel == MySliderStyleConfiguration.ValueLabel {
    init(_ configuration: MySliderStyleConfiguration) {
        self._value = configuration.$value
        self.bounds = configuration.bounds
        self.label = configuration.label
        self.minimumValueLabel = configuration.minimumValueLabel
        self.maximumValueLabel = configuration.maximumValueLabel
        self.onEditingChanged = configuration.onEditingChanged
    }
}

// MARK: - Style Protocol

protocol MySliderStyle: DynamicProperty {
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: Configuration) -> Body

    typealias Configuration = MySliderStyleConfiguration
}

// MARK: - Resolved Style

extension MySliderStyle {
    func resolve(configuration: Configuration) -> some View {
        ResolvedMySliderStyle(configuration: configuration, style: self)
    }
}

struct ResolvedMySliderStyle<Style: MySliderStyle>: View {
    var configuration: Style.Configuration

    var style: Style

    var body: Style.Body {
        style.makeBody(configuration: configuration)
    }
}

// MARK: - Style Configuration

struct MySliderStyleConfiguration {
    struct Label: View {
        let underlyingLabel: AnyView

        init(_ label: some View) {
            self.underlyingLabel = AnyView(label)
        }

        var body: some View {
            underlyingLabel
        }
    }

    struct ValueLabel: View {
        let underlyingLabel: AnyView

        init(_ label: some View) {
            self.underlyingLabel = AnyView(label)
        }

        var body: some View {
            underlyingLabel
        }
    }

    @Binding
    var value: Double

    let bounds: ClosedRange<Double>

    let label: Label

    let minimumValueLabel: ValueLabel

    let maximumValueLabel: ValueLabel

    let onEditingChanged: (Bool) -> Void

    init<Label: View, ValueLabel: View>(
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        label: Label,
        minimumValueLabel: ValueLabel,
        maximumValueLabel: ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        self._value = value
        self.bounds = bounds
        self.label = label as? MySliderStyleConfiguration.Label ?? .init(label)
        self.minimumValueLabel = minimumValueLabel as? MySliderStyleConfiguration.ValueLabel ?? .init(minimumValueLabel)
        self.maximumValueLabel = maximumValueLabel as? MySliderStyleConfiguration.ValueLabel ?? .init(maximumValueLabel)
        self.onEditingChanged = onEditingChanged
    }
}

// MARK: - Environment

struct MySliderStyleKey: EnvironmentKey {
    static var defaultValue: any MySliderStyle = DefaultMySliderStyle()
}

extension EnvironmentValues {
    var mySliderStyle: any MySliderStyle {
        get { self[MySliderStyleKey.self] }
        set { self[MySliderStyleKey.self] = newValue }
    }
}

extension View {
    func mySliderStyle(_ style: some MySliderStyle) -> some View {
        environment(\.mySliderStyle, style)
    }
}

// MARK: - Default Style

struct DefaultMySliderStyle: MySliderStyle {
    func makeBody(configuration: Configuration) -> some View {
        Slider(
            value: configuration.$value,
            in: configuration.bounds,
            label: { configuration.label },
            minimumValueLabel: { configuration.minimumValueLabel },
            maximumValueLabel: { configuration.maximumValueLabel },
            onEditingChanged: configuration.onEditingChanged
        )
    }
}

extension MySliderStyle where Self == DefaultMySliderStyle {
    static var `default`: Self { .init() }
}

// MARK: - Custom Style

struct CustomMySliderStyle: MySliderStyle {
    @Environment(\.isEnabled)
    var isEnabled

    @GestureState
    var valueAtStartOfDrag: Double?

    func drag(updating value: Binding<Double>, in bounds: ClosedRange<Double>, width: Double) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($valueAtStartOfDrag) { dragValue, state, _ in
                if state == nil {
                    state = value.wrappedValue
                }
            }
            .onChanged { dragValue in
                if let newValue = valueForTranslation(dragValue.translation.width, in: bounds, width: width) {
                    var transaction = Transaction()
                    transaction.isContinuous = true
                    withTransaction(transaction) {
                        value.wrappedValue = newValue
                    }
                }
            }
            .onEnded { dragValue in
                if let newValue = valueForTranslation(dragValue.translation.width, in: bounds, width: width) {
                    value.wrappedValue = newValue
                }
            }
    }

    func makeBody(configuration: Configuration) -> some View {
        LabeledContent {
            HStack {
                Button {
                    withAnimation {
                        configuration.value = configuration.bounds.lowerBound
                    }
                } label: {
                    configuration.minimumValueLabel
                }
                .buttonStyle(.plain)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.regularMaterial)
                        Rectangle()
                            .fill(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.gray.opacity(0.5)))
                            .frame(width: relativeValue(for: configuration.value, in: configuration.bounds) * proxy.size.width)
                    }
                    .contentShape(Rectangle())
                    .gesture(drag(updating: configuration.$value, in: configuration.bounds, width: proxy.size.width))
                }
                .frame(height: 44)
                .mask(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    withAnimation {
                        configuration.value = configuration.bounds.upperBound
                    }
                } label: {
                    configuration.maximumValueLabel
                }
                .buttonStyle(.plain)
            }
        } label: {
            configuration.label
        }
        .onChange(of: valueAtStartOfDrag != nil) { newValue in
            configuration.onEditingChanged(newValue)
        }
    }

    func relativeValue(for value: Double, in bounds: ClosedRange<Double>) -> Double {
        let boundsLength = bounds.upperBound - bounds.lowerBound
        let fraction = (value - bounds.lowerBound) / boundsLength
        return max(0, min(fraction, 1))
    }

    func valueForTranslation(_ x: Double, in bounds: ClosedRange<Double>, width: Double) -> Double? {
        guard let initialValue = valueAtStartOfDrag, width > 0 else { return nil }
        let relativeTranslation = x / width
        let boundsLength = bounds.upperBound - bounds.lowerBound
        let scaledTranslation = relativeTranslation * boundsLength
        let newValue = initialValue + scaledTranslation
        let clamped = max(bounds.lowerBound, min(newValue, bounds.upperBound))
        return clamped
    }
}

extension MySliderStyle where Self == CustomMySliderStyle {
    static var custom: Self { .init() }
}

// MARK: - Example View

struct ContentView: View {
    @State
    var value = 0.2

    @State
    var value2 = 0.2

    @State
    var isEnabled = true

    var body: some View {
        VStack(spacing: 32) {
            Toggle("Enabled", isOn: $isEnabled)

            Group {
                MySlider(value: $value, in: 0.0...1.0) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                } onEditingChanged: { isEditing in
                    print(isEditing)
                }

                Divider()

                MySlider(value: $value2, in: 0.0...1.0) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                } onEditingChanged: { isEditing in
                    print(isEditing)
                }
                .mySliderStyle(.custom)
                .labelsHidden()
            }
            .disabled(!isEnabled)
        }
        .tint(.orange)
        .padding()
        .frame(width: 320)
    }
}

PlaygroundPage.current.setLiveView(ContentView())
