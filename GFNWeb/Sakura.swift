import UIKit

// MARK: - Hoa đào rơi (CAEmitterLayer) + màn hình mở đầu

enum Sakura {
    /// Vẽ một cánh hoa đào (hình giọt, có khía nhỏ ở đầu) bằng code, không cần file ảnh
    static func petalImage(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 22, height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 11, y: 28))
            p.addCurve(to: CGPoint(x: 1, y: 9), controlPoint1: CGPoint(x: 1, y: 24), controlPoint2: CGPoint(x: -3, y: 15))
            p.addCurve(to: CGPoint(x: 9, y: 1), controlPoint1: CGPoint(x: 2, y: 4), controlPoint2: CGPoint(x: 6, y: 0))
            p.addLine(to: CGPoint(x: 11, y: 4))
            p.addLine(to: CGPoint(x: 13, y: 1))
            p.addCurve(to: CGPoint(x: 21, y: 9), controlPoint1: CGPoint(x: 16, y: 0), controlPoint2: CGPoint(x: 20, y: 4))
            p.addCurve(to: CGPoint(x: 11, y: 28), controlPoint1: CGPoint(x: 25, y: 15), controlPoint2: CGPoint(x: 21, y: 24))
            p.close()
            color.setFill()
            p.fill()
        }
    }
}

/// Lớp hoa đào rơi, không nhận chạm
final class SakuraView: UIView {
    private let emitter = CAEmitterLayer()
    private let intensity: Float

    init(intensity: Float = 1) {
        self.intensity = intensity
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitter.emitterShape = .line
        emitter.renderMode = .unordered
        let colors: [UIColor] = [
            UIColor(red: 1.00, green: 0.78, blue: 0.87, alpha: 1),
            UIColor(red: 1.00, green: 0.65, blue: 0.79, alpha: 1),
            UIColor(red: 1.00, green: 0.88, blue: 0.93, alpha: 1),
        ]
        emitter.emitterCells = colors.enumerated().map { (i, c) in
            let cell = CAEmitterCell()
            cell.contents = Sakura.petalImage(c).cgImage
            cell.birthRate = 2.2 * intensity
            cell.lifetime = 14
            cell.velocity = 55 + CGFloat(i) * 12
            cell.velocityRange = 30
            cell.emissionLongitude = .pi / 2          // rơi xuống
            cell.emissionRange = .pi / 7
            cell.xAcceleration = 14                   // gió nhẹ thổi sang phải
            cell.yAcceleration = 8
            cell.spin = 0.9
            cell.spinRange = 2.2
            cell.scale = 0.55
            cell.scaleRange = 0.35
            cell.alphaRange = 0.25
            cell.alphaSpeed = -0.02
            return cell
        }
        layer.addSublayer(emitter)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
        emitter.emitterSize = CGSize(width: bounds.width * 1.3, height: 1)
    }
}

/// Màn hình mở đầu: ảnh nhân vật + hoa đào rơi, tự mờ dần sau vài giây (chạm để bỏ qua)
final class SplashView: UIView {
    private let imageView = UIImageView(image: UIImage(named: "Waifu"))
    private let sakura = SakuraView(intensity: 2.2)
    private var finished = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.16, green: 0.06, blue: 0.12, alpha: 1)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        // Phủ một lớp gradient hồng để chữ dễ đọc
        let g = CAGradientLayer()
        g.colors = [UIColor.clear.cgColor, UIColor(red: 0.45, green: 0.1, blue: 0.28, alpha: 0.75).cgColor]
        g.locations = [0.55, 1]
        layer.addSublayer(g)
        gradient = g

        addSubview(sakura)

        title.text = "HKnow  ♡"
        title.font = .systemFont(ofSize: 34, weight: .heavy)
        title.textColor = .white
        title.layer.shadowColor = UIColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1).cgColor
        title.layer.shadowOpacity = 0.9
        title.layer.shadowRadius = 8
        title.layer.shadowOffset = .zero
        title.textAlignment = .center
        addSubview(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var gradient: CAGradientLayer?
    private let title = UILabel()

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        sakura.frame = bounds
        gradient?.frame = bounds
        title.frame = CGRect(x: 0, y: bounds.height - 90, width: bounds.width, height: 44)
    }

    /// Hiện lên trên `host`, tự biến mất sau `duration` giây
    func show(in host: UIView, duration: TimeInterval = 3.6) {
        frame = host.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(self)
        alpha = 0
        UIView.animate(withDuration: 0.5) { self.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.dismiss() }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { dismiss() }

    private func dismiss() {
        guard !finished else { return }
        finished = true
        UIView.animate(withDuration: 0.8, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
    }
}
