package com.shoo.app.features.onboarding

import android.net.Uri
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.VideoView
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.shoo.app.R
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.shooSmooth
import com.shoo.app.components.systemTextStyle
import com.shoo.app.support.Log
import com.shoo.app.support.t
import kotlinx.coroutines.launch

/**
 * ON-04 "Still can't? Watch the video": a full-screen player (`R.raw.onboarding_tutorial`) with the system controls.
 * `onDismiss`: the close button or Back (iOS `@Environment(\.dismiss)` of the full-screen cover).
 * iOS: Picture in Picture keeps the video over Settings; Android PiP is per Activity, so the video plays in the app only.
 */
@Composable
fun TutorialVideoPlayer(onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    var failed by remember { mutableStateOf(false) }
    // iOS `.fullScreenCover`: the cover slides up from the bottom edge and back down on dismiss.
    val cover = remember { Animatable(1f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { cover.animateTo(0f, shooSmooth(0.5)) }
    val dismiss: () -> Unit = {
        scope.launch {
            cover.animateTo(1f, shooSmooth(0.5))
            onDismiss()
        }
    }
    Dialog(
        onDismissRequest = dismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .graphicsLayer { translationY = cover.value * size.height }
                .background(Color.Black),
        ) {
            if (failed) {
                Text(
                    t("The video isn't available right now."),
                    style = systemTextStyle(SystemTextStyle.TITLE3).copy(color = Color.White, textAlign = TextAlign.Center),
                    modifier = Modifier.align(Alignment.Center).padding(32.dp),
                )
            } else {
                AndroidView(
                    factory = { context ->
                        val video = VideoView(context)
                        FrameLayout(context).apply {
                            addView(video, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
                            val controls = MediaController(context)
                            controls.setAnchorView(this)
                            video.setMediaController(controls)
                            video.setVideoURI(Uri.parse("android.resource://${context.packageName}/${R.raw.onboarding_tutorial}"))
                            video.setOnPreparedListener { video.start() }
                            video.setOnErrorListener { _, what, extra ->
                                Log.app.error("Tutorial video failed", "$what/$extra")
                                failed = true
                                true
                            }
                        }
                    },
                    onRelease = { frame -> (frame.getChildAt(0) as? VideoView)?.stopPlayback() },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            val close = t("Close")
            Box(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(16.dp)
                    .size(44.dp)
                    .background(Color.Black.copy(alpha = 0.6f), CircleShape)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Button,
                        onClick = dismiss,
                    )
                    .semantics {
                        contentDescription = close
                        testTag = "video.close"
                    },
                contentAlignment = Alignment.Center,
            ) {
                // `.font(.headline)`: 17 semibold.
                SfSymbol("xmark", pointSize = 17f, tint = Color.White)
            }
        }
    }
}
