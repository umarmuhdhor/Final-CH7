package com.shoo.app.features.onboarding

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.R
import com.shoo.app.components.LightOnly
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.shooDefault
import com.shoo.app.support.t
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

/** One ON-01 slide. `title`, `message`: catalog keys. */
private class Slide(val id: Int, val image: Int, val title: String, val message: String)

private val slides = listOf(
    Slide(
        id = 0,
        image = R.drawable.onboarding_slide1,
        title = "Browse calmer, feeling safe.",
        message = "No worrying about dangerous sites. Let Shoo do the work for you and your family.",
    ),
    Slide(
        id = 1,
        image = R.drawable.onboarding_slide2,
        title = "Looks real, may not be safe.\nLet Shoo check.",
        message = "Shoo checks the pages you open and blocks fake sites before they can hurt you.",
    ),
)

/** Figma "Horizontal Slider": the 62 pt button ends 66 pt above the screen bottom (32 over the bottom inset). */
private val ControlsBottom = 32.dp
private val NextSize = 62.dp

/**
 * ON-01: two swipeable slides with Skip and a round Next button (Figma 1352:4375, 1352:4039). First run only.
 * The brand splash before them (Figma 110:3585) is `LaunchSplash`, over the first screen of every launch.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SplashView(model: OnboardingModel, modifier: Modifier = Modifier) {
    LightOnly {
        val pager = rememberPagerState { slides.size }
        val scope = rememberCoroutineScope()
        val isLast = pager.currentPage == slides.size - 1
        val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()

        BoxWithConstraints(modifier = modifier.fillMaxSize().background(OnboardingTheme.card)) {
            // Figma: 463 of 874 pt is illustration; scales with the screen so small phones keep room for text.
            // Drawn edge to edge, so this is the full screen height.
            val headerHeight = (maxHeight.value * 463f / 874f).roundToInt().dp
            // iOS `.safeAreaInset(edge: .bottom) { controls }`: the slides scroll clear of the buttons.
            val controlsRoom = NextSize + ControlsBottom + navBottom

            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { index ->
                val slide = slides[index]
                SlidePage(
                    image = slide.image,
                    title = slide.title,
                    message = slide.message,
                    headerHeight = headerHeight,
                    bottomRoom = controlsRoom,
                    modifier = Modifier.semantics { testTag = "splash.slide.${slide.id}" },
                )
            }

            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = ControlsBottom),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .sizeIn(minWidth = 44.dp, minHeight = 44.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                            onClick = model::skipSplash,
                        )
                        .semantics { testTag = "splash.skip" },
                    contentAlignment = Alignment.CenterStart,
                ) {
                    // Figma "Subhead/Regular".
                    Text(t("Skip"), style = onboardingFont(17f, rounded = true).copy(color = OnboardingTheme.ink))
                }

                Spacer(Modifier.weight(1f))

                val interaction = remember { MutableInteractionSource() }
                val label = t(if (isLast) "Get started" else "Next")
                Box(
                    modifier = Modifier
                        .onboardingPress(interaction)
                        .size(NextSize)
                        // Figma "Button/Full/Circle": gradient only, no shadow.
                        .background(OnboardingTheme.buttonGradient, CircleShape)
                        .clickable(interactionSource = interaction, indication = null, role = Role.Button) {
                            if (isLast) {
                                model.skipSplash()
                            } else {
                                // `withAnimation { page += 1 }`: SwiftUI's default animation.
                                scope.launch { pager.animateScrollToPage(pager.currentPage + 1, animationSpec = shooDefault()) }
                            }
                        }
                        .semantics {
                            contentDescription = label
                            testTag = "splash.next"
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    // Figma sets the symbol as SF Pro Rounded Semibold 20 text.
                    SfSymbol("arrow.right", pointSize = 20f, tint = OnboardingTheme.onButton)
                }
            }
        }
    }
}

@Composable
private fun SlidePage(
    image: Int,
    title: String,
    message: String,
    headerHeight: Dp,
    bottomRoom: Dp,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        // The asset already ends in Figma "Rectangle 953", the fade into the white page.
        Image(
            painter = painterResource(image),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            alignment = Alignment.BottomCenter,
            modifier = Modifier.fillMaxWidth().height(headerHeight).clipToBounds(),
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 24.dp, end = 24.dp, top = 55.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(t(title), style = onboardingTitleStyle(), modifier = Modifier.fillMaxWidth().semantics { heading() })
            Text(t(message), style = onboardingBodyStyle(), modifier = Modifier.fillMaxWidth())
        }
        Spacer(Modifier.height(bottomRoom))
    }
}
