package de.kitshn.ui.route.onboarding

import androidx.compose.runtime.Composable
import com.multiplatform.webview.web.PlatformWebViewParams
import de.kitshn.api.tandoor.TandoorCredentials

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
): PlatformWebViewParams? = null
