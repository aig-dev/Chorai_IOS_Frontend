import Foundation

/// Local registration details. The email code is checked only by registration.
public struct RegistrationDraft {
    public enum Step: String, Sendable {
        case email, code, username, password, confirm
    }

    public var email: String {
        didSet {
            guard oldValue != email else { return }
            code = ""
            sentEmail = nil
            resendDeadline = nil
        }
    }
    public var code: String {
        get { enteredCode }
        set { enteredCode = String(newValue.prefix(6)) }
    }
    public var username: String
    public var password: String
    public var confirmPassword: String

    private var enteredCode = ""
    private var sentEmail: String?
    private var resendDeadline: Date?

    public init(
        email: String = "",
        code: String = "",
        username: String = "",
        password: String = "",
        confirmPassword: String = ""
    ) {
        self.email = email
        self.username = username
        self.password = password
        self.confirmPassword = confirmPassword
        self.code = code
        if !code.isEmpty && !email.isEmpty {
            // A prefilled draft already has a code for this address.
            sentEmail = email
        }
    }

    public var codeWasSent: Bool { sentEmail == email }

    @discardableResult
    public mutating func markCodeSent(to address: String, at time: Date) -> Bool {
        guard address == email, canContinue(.email) else { return false }
        sentEmail = address
        resendDeadline = time.addingTimeInterval(60)
        return true
    }

    public func resendSeconds(at time: Date) -> Int {
        guard let resendDeadline else { return 0 }
        return max(0, Int(ceil(resendDeadline.timeIntervalSince(time))))
    }

    public func canContinue(_ step: Step) -> Bool {
        switch step {
        case .email:
            return email.range(
                of: #"\A[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z"#,
                options: .regularExpression
            ) != nil
        case .code:
            return codeWasSent && code.count == 6
        case .username:
            return username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .password:
            return password.count >= 8
                && password.rangeOfCharacter(from: .letters) != nil
                && password.rangeOfCharacter(from: .decimalDigits) != nil
        case .confirm:
            return !confirmPassword.isEmpty
        }
    }

    public var canRegister: Bool {
        canContinue(.email) && canContinue(.code) && canContinue(.username)
            && canContinue(.password) && password == confirmPassword
    }
}
