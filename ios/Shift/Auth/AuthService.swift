import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import UIKit

/// Apple / Google でのログイン状態。ログインは任意で、していなくても端末内だけで使える
@Observable
final class AuthService {
    struct Account {
        let uid: String
        let name: String?
        let email: String?
        let provider: String
    }

    private(set) var account: Account?
    var errorMessage: String?
    private(set) var busy = false

    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    init() {
        account = Self.account(from: Auth.auth().currentUser)
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.account = Self.account(from: user)
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    private static func account(from user: User?) -> Account? {
        guard let user else { return nil }
        let id = user.providerData.first?.providerID
        let provider = id == "apple.com" ? "Apple" : id == "google.com" ? "Google" : "アカウント"
        return Account(uid: user.uid, name: user.displayName, email: user.email, provider: provider)
    }

    // MARK: Apple

    /// SignInWithAppleButton の onRequest で呼ぶ
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// SignInWithAppleButton の onCompletion で呼ぶ
    func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = "Apple でのログインに失敗しました" }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple でのログインに失敗しました"
                return
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: cred.fullName)
            await signIn(with: credential, failure: "Apple でのログインに失敗しました")
        }
    }

    // MARK: Google

    @MainActor
    func signInWithGoogle() async {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let presenter = Self.topViewController() else {
            errorMessage = "Google でのログインを開始できませんでした"
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        busy = true
        defer { busy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google でのログインに失敗しました"
                return
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: result.user.accessToken.tokenString)
            await signIn(with: credential, failure: "Google でのログインに失敗しました")
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                errorMessage = "Google でのログインに失敗しました"
            }
        }
    }

    // MARK: 共通

    private func signIn(with credential: AuthCredential, failure: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = failure
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = "ログアウトに失敗しました"
        }
    }

    /// アカウントを削除する。しばらく前にログインしたままだと拒否されるので、そのときは再ログインを促す
    @discardableResult
    func deleteAccount() async -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        busy = true
        defer { busy = false }
        do {
            try await user.delete()
            GIDSignIn.sharedInstance.signOut()
            return true
        } catch {
            if (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue {
                errorMessage = "セキュリティのため、もう一度ログインしてから削除してください"
            } else {
                errorMessage = "アカウントを削除できませんでした"
            }
            return false
        }
    }

    // MARK: 部品

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        while out.count < length {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { continue }
            // 文字は 64 種類なので、256 を割り切れて偏りが出ない
            for b in bytes where out.count < length {
                out.append(chars[Int(b) % chars.count])
            }
        }
        return out
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
