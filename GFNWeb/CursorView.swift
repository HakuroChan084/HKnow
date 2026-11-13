import UIKit

/// Con trỏ chuột kiểu Windows (mũi tên trắng viền đen) do app tự vẽ.
/// Đầu mũi tên nằm đúng tại điểm được truyền vào `place(at:)`.
final class CursorView: UIView {

    private let arrow = CAShapeLayer()
    private static let tip = CGPoint(x: 1, y: 1)

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 16, height: 24))
        isUserInteractionEnabled = false
        isHidden = true
        backgroundColor = .clear

        let p = UIBezierPath()
        p.move(to: CGPoint(x: 1, y: 1))
        p.addLine(to: CGPoint(x: 1, y: 18))
        p.addLine(to: CGPoint(x: 5, y: 14.2))
        p.addLine(to: CGPoint(x: 8, y: 21))
        p.addLine(to: CGPoint(x: 10.6, y: 19.9))
        p.addLine(to: CGPoint(x: 7.7, y: 13.2))
        p.addLine(to: CGPoint(x: 13, y: 13.2))
        p.close()

        arrow.path = p.cgPath
        arrow.fillColor = UIColor.white.cgColor
        arrow.strokeColor = UIColor.black.cgColor
        arrow.lineWidth = 1.2
        arrow.lineJoin = .round
        arrow.shadowColor = UIColor.black.cgColor
        arrow.shadowOpacity = 0.35
        arrow.shadowRadius = 1.5
        arrow.shadowOffset = CGSize(width: 0.5, height: 1)
        layer.addSublayer(arrow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func place(at point: CGPoint) {
        frame = CGRect(
            x: point.x - CursorView.tip.x,
            y: point.y - CursorView.tip.y,
            width: bounds.width,
            height: bounds.height
        )
    }
}
