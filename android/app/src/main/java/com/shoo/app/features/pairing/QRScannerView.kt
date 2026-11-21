package com.shoo.app.features.pairing

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import com.shoo.app.app.AppConfig
import com.shoo.app.components.SystemColors
import com.shoo.app.components.SystemTextStyle
import com.shoo.app.components.readableSecondary
import com.shoo.app.components.systemTextStyle
import com.shoo.app.features.activity.OnResume
import com.shoo.app.support.Log
import com.shoo.app.support.t
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Camera access, like `AVAuthorizationStatus`. */
private enum class CameraAccess { NOT_DETERMINED, AUTHORIZED, DENIED }

/**
 * PR-01 "Scan QR": live camera, QR codes only, nothing recorded or saved (SECURITY §3 P7). The camera permission is
 * asked only when this tab is opened (just in time). `onPayload` comes last so the Swift trailing closure stays one.
 * iOS: VisionKit draws a highlight around a recognised code; the CameraX preview here has none.
 */
@Composable
fun QRScannerView(modifier: Modifier = Modifier, onPayload: (String) -> Unit) {
    val context = LocalContext.current
    val hasCamera = remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    val scannerAvailable = AppConfig.cameraEnabled && hasCamera
    var access by remember { mutableStateOf(if (isGranted(context)) CameraAccess.AUTHORIZED else CameraAccess.NOT_DETERMINED) }
    var scannerFailed by remember { mutableStateOf(false) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        access = if (granted) CameraAccess.AUTHORIZED else CameraAccess.DENIED
    }
    LaunchedEffect(Unit) {
        if (scannerAvailable && access == CameraAccess.NOT_DETERMINED) launcher.launch(Manifest.permission.CAMERA)
    }
    // Back from Settings with the camera allowed, or the camera free again: try once more.
    OnResume {
        if (isGranted(context)) access = CameraAccess.AUTHORIZED
        scannerFailed = false
    }

    Box(modifier.semantics { testTag = "connect.scanner" }) {
        when {
            // Android copy: "this phone" instead of "this iPhone".
            !scannerAvailable -> ScannerNote("Scanning isn't available on this phone. Enter the code instead.")
            access == CameraAccess.AUTHORIZED && scannerFailed ->
                // Camera busy or blocked by a policy.
                ScannerNote("Scanning isn't available right now. Enter the code instead.")
            access == CameraAccess.AUTHORIZED -> {
                val label = t("Camera. Point it at the QR code on your guardian's phone.")
                CameraQRScanner(
                    onPayload = onPayload,
                    onFailure = { scannerFailed = true },
                    modifier = Modifier
                        .fillMaxSize()
                        .heightIn(min = 280.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .semantics { contentDescription = label },
                )
            }
            access == CameraAccess.NOT_DETERMINED -> Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(Modifier.size(20.dp), color = SystemColors.gray, strokeWidth = 2.dp)
            }
            else -> Column(
                Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                ScannerNote("Shoo can't use the camera. Allow it in Settings, or enter the code instead.")
                Box(
                    Modifier
                        .heightIn(min = 44.dp)
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
                            openAppSettings(context)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(t("Open Settings"), style = systemTextStyle(SystemTextStyle.BODY), color = SystemColors.blue)
                }
            }
        }
    }
}

private fun isGranted(context: Context): Boolean =
    ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

/** iOS `UIApplication.openSettingsURLString`: this app's page in Settings. */
private fun openAppSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    try {
        context.startActivity(intent)
    } catch (_: Exception) {
    }
}

/** `note(_:)`: `text` is a catalog key. */
@Composable
private fun ScannerNote(text: String) {
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 120.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(t(text), style = systemTextStyle(SystemTextStyle.BODY), color = readableSecondary, textAlign = TextAlign.Center)
    }
}

/**
 * CameraX preview + a zxing decode of every frame (iOS `DataScannerViewController` with `.barcode(symbologies: [.qr])`).
 * Frames stay in memory; nothing is recorded or saved.
 */
@Composable
private fun CameraQRScanner(onPayload: (String) -> Unit, onFailure: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentPayload by rememberUpdatedState(onPayload)
    val currentFailure by rememberUpdatedState(onFailure)
    val previewView = remember { PreviewView(context).apply { scaleType = PreviewView.ScaleType.FILL_CENTER } }

    DisposableEffect(lifecycleOwner) {
        val executor: ExecutorService = Executors.newSingleThreadExecutor()
        val mainExecutor = ContextCompat.getMainExecutor(context)
        // The same code seen again (it left the frame and came back) is answered once.
        var lastPayload: String? = null
        val reader = QRCodeReader()
        val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
        var provider: ProcessCameraProvider? = null
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            try {
                val cameraProvider = future.get()
                provider = cameraProvider
                val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(executor) { image ->
                    val text = decode(image, reader, hints)
                    if (text != null) {
                        mainExecutor.execute {
                            if (text != lastPayload) {
                                lastPayload = text
                                currentPayload(text)
                            }
                        }
                    }
                }
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
            } catch (error: Exception) {
                Log.ui.error("QR scanner failed", error)
                currentFailure()
            }
        }, mainExecutor)
        onDispose {
            provider?.unbindAll()
            executor.shutdown()
        }
    }
    AndroidView(factory = { previewView }, modifier = modifier)
}

/** The QR text in this frame (its luminance plane), or null. Always closes the frame. */
private fun decode(image: ImageProxy, reader: QRCodeReader, hints: Map<DecodeHintType, Any>): String? {
    try {
        val plane = image.planes.firstOrNull() ?: return null
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val width = image.width
        val height = image.height
        val data = ByteArray(buffer.remaining())
        buffer.get(data)
        val source = PlanarYUVLuminanceSource(data, rowStride, height, 0, 0, width, height, false)
        return try {
            reader.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
        } catch (_: NotFoundException) {
            null
        } catch (_: Exception) {
            null
        } finally {
            reader.reset()
        }
    } catch (_: Exception) {
        return null
    } finally {
        image.close()
    }
}
