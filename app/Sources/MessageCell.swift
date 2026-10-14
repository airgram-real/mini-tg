import UIKit

extension MessageEntry.Kind {
    var isMedia: Bool {
        if case .photo = self { return true }
        return false
    }
    var fileId: Int64 {
        switch self {
        case .photo(let f, _, _): return f
        case .document(let f, _, _): return f
        case .text: return 0
        }
    }
}

final class MessageCell: UITableViewCell {
    static let maxWidth: CGFloat = 460

    private let bubble = UIView()
    private let textLabelInternal = UILabel()
    private let metaLabel = UILabel()
    private let imageViewInternal = UIImageView()
    private let fileButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .gray)
    private var entry: MessageEntry?
    private var onFileTap: ((MessageEntry) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        bubble.layer.cornerRadius = 16
        bubble.layer.masksToBounds = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)

        textLabelInternal.font = .systemFont(ofSize: 16)
        textLabelInternal.numberOfLines = 0
        textLabelInternal.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(textLabelInternal)

        metaLabel.font = .systemFont(ofSize: 11)
        metaLabel.textColor = UIColor(white: 0, alpha: 0.4)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(metaLabel)

        imageViewInternal.contentMode = .scaleAspectFill
        imageViewInternal.clipsToBounds = true
        imageViewInternal.layer.cornerRadius = 12
        imageViewInternal.translatesAutoresizingMaskIntoConstraints = false
        imageViewInternal.isHidden = true
        bubble.addSubview(imageViewInternal)

        fileButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        fileButton.setTitleColor(.tgBlue, for: .normal)
        fileButton.isHidden = true
        fileButton.translatesAutoresizingMaskIntoConstraints = false
        fileButton.addTarget(self, action: #selector(fileTapped), for: .touchUpInside)
        bubble.addSubview(fileButton)

        activity.hidesWhenStopped = true
        activity.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(activity)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fileTapped() {
        guard let e = entry else { return }
        onFileTap?(e)
    }

    static func estimatedHeight(for entry: MessageEntry, width: CGFloat) -> CGFloat {
        let bubbleWidth = min(width - 40, maxWidth) - 28
        switch entry.kind {
        case .text:
            let h = (entry.text as NSString).boundingRect(
                with: CGSize(width: bubbleWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
                context: nil).height
            return h + 46
        case .photo(_, let w, let h):
            let aspect = (w > 0 && h > 0) ? CGFloat(h) / CGFloat(w) : 0.75
            let imgH = min(CGFloat(bubbleWidth) * aspect, 400)
            return imgH + 50
        case .document(_, _, _):
            return 72
        }
    }

    func configure(entry: MessageEntry,
                   localPath: @escaping (Int64) -> String?,
                   senderTitle: @escaping (Int64) -> String?) {
        self.entry = entry
        let isOut = entry.isOut
        bubble.backgroundColor = isOut ? .tgOutgoing : .tgIncoming
        textLabelInternal.textColor = .black
        metaLabel.text = timeString(entry.date)

        // out/in alignment
        let isPad = UIScreen.main.bounds.width > 700
        let maxBubble = isPad ? MessageCell.maxWidth : UIScreen.main.bounds.width - 80

        // Remove old constraints referencing bubble edges for content
        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints.removeAll()

        var bottom: NSLayoutYAxisAnchor = bubble.bottomAnchor

        switch entry.kind {
        case .text:
            imageViewInternal.isHidden = true
            fileButton.isHidden = true
            activity.stopAnimating()
            textLabelInternal.isHidden = false
            textLabelInternal.text = entry.text
            let w = min(maxBubble - 28, UIScreen.main.bounds.width * 0.7)
            contentConstraints.append(textLabelInternal.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8))
            contentConstraints.append(textLabelInternal.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12))
            contentConstraints.append(textLabelInternal.widthAnchor.constraint(lessThanOrEqualToConstant: w))
            contentConstraints.append(metaLabel.topAnchor.constraint(equalTo: textLabelInternal.bottomAnchor, constant: 4))
            bottom = metaLabel.bottomAnchor
        case .photo(let fileId, _, _):
            textLabelInternal.isHidden = true
            fileButton.isHidden = true
            imageViewInternal.isHidden = false
            let path = localPath(fileId)
            if let path = path, let img = UIImage(contentsOfFile: path) {
                activity.stopAnimating()
                imageViewInternal.image = img
            } else {
                activity.startAnimating()
            }
            let aspect: CGFloat = 0.75
            let w = min(maxBubble - 20, 300)
            contentConstraints.append(imageViewInternal.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 6))
            contentConstraints.append(imageViewInternal.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 6))
            contentConstraints.append(imageViewInternal.widthAnchor.constraint(equalToConstant: w))
            contentConstraints.append(imageViewInternal.heightAnchor.constraint(equalToConstant: w * aspect))
            contentConstraints.append(metaLabel.topAnchor.constraint(equalTo: imageViewInternal.bottomAnchor, constant: 4))
            bottom = metaLabel.bottomAnchor
        case .document(_, let name, let size):
            textLabelInternal.isHidden = true
            imageViewInternal.isHidden = true
            fileButton.isHidden = false
            let sizeText = size > 0 ? " (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))" : ""
            let path = localPath(entry.kind.fileId)
            let downloaded = path != nil
            fileButton.setTitle((downloaded ? "\u{1F4C4} " : "\u{2B07} ") + name + sizeText, for: .normal)
            if !downloaded { activity.startAnimating() } else { activity.stopAnimating() }
            contentConstraints.append(fileButton.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10))
            contentConstraints.append(fileButton.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12))
            contentConstraints.append(fileButton.trailingAnchor.constraint(lessThanOrEqualTo: bubble.trailingAnchor, constant: -12))
            contentConstraints.append(metaLabel.topAnchor.constraint(equalTo: fileButton.bottomAnchor, constant: 2))
            bottom = metaLabel.bottomAnchor
        }

        contentConstraints.append(metaLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12))
        contentConstraints.append(metaLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6))
        contentConstraints.append(bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4))
        contentConstraints.append(bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4))
        contentConstraints.append(bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubble))

        if isOut {
            contentConstraints.append(bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12))
            contentConstraints.append(bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12))
        } else {
            contentConstraints.append(bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12))
            contentConstraints.append(bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12))
        }

        NSLayoutConstraint.activate(contentConstraints)
        setNeedsLayout()
        layoutIfNeeded()
    }

    private var contentConstraints: [NSLayoutConstraint] = []

    private func timeString(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}
