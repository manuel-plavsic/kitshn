package de.kitshn.ui.route.onboarding

import android.content.Context
import android.security.KeyChain
import android.webkit.ClientCertRequest
import android.webkit.WebView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import co.touchlab.kermit.Logger
import com.multiplatform.webview.web.AccompanistWebViewClient
import com.multiplatform.webview.web.PlatformWebViewParams
import de.kitshn.api.tandoor.TandoorCredentials
import de.kitshn.api.tandoor.loadPkcs12CertificateBundle
import java.security.PrivateKey
import java.security.cert.X509Certificate
import kotlin.concurrent.thread

private const val TAG = "OnboardingSignInBrowser"

// needed for jvm implementation
@Composable
actual fun InitializeWebView(
    onInitialized: () -> Unit
) {
    onInitialized()
}

@Composable
actual fun rememberSignInPlatformWebViewParams(
    credentials: TandoorCredentials
): PlatformWebViewParams? {
    val context = LocalContext.current.applicationContext
    return remember(context, credentials) {
        if(credentials.mtlsCertificateAlias == null && credentials.mtlsCertificateData == null)
            return@remember null

        // WebView remembers declined certificate requests per host for the app's lifetime
        WebView.clearClientCertPreferences(null)

        PlatformWebViewParams(client = MtlsWebViewClient(context, credentials))
    }
}

/**
 * Answers client certificate requests with the identity selected in the sign-in form
 * (Android KeyChain alias or imported PKCS12 bundle).
 */
private class MtlsWebViewClient(
    private val context: Context,
    private val credentials: TandoorCredentials,
) : AccompanistWebViewClient() {

    override fun onReceivedClientCertRequest(view: WebView?, request: ClientCertRequest) {
        // KeyChain must not be accessed on the main thread
        thread(name = "mtls-webview-cert") {
            val identity = try {
                loadIdentity(request)
            } catch(e: Exception) {
                Logger.e(TAG, e) { "Loading client certificate failed" }
                null
            }

            if(identity == null) {
                request.cancel()
            } else {
                request.proceed(identity.first, identity.second)
            }
        }
    }

    private fun loadIdentity(request: ClientCertRequest): Pair<PrivateKey, Array<X509Certificate>>? {
        credentials.mtlsCertificateAlias?.let { alias ->
            val key = KeyChain.getPrivateKey(context, alias) ?: return null
            val chain = KeyChain.getCertificateChain(context, alias) ?: return null
            return key to chain
        }

        val keyManager = loadPkcs12CertificateBundle(
            credentials.mtlsCertificateData,
            credentials.mtlsCertificatePassword,
        )?.keyManager ?: return null

        val alias = keyManager.chooseClientAlias(request.keyTypes, request.principals, null)
            ?: return null
        val key = keyManager.getPrivateKey(alias) ?: return null
        val chain = keyManager.getCertificateChain(alias) ?: return null
        return key to chain
    }
}
