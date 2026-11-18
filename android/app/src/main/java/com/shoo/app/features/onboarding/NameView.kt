package com.shoo.app.features.onboarding

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.shoo.app.components.AvatarCatalog
import com.shoo.app.components.FigmaFont
import com.shoo.app.components.LocalAppLanguage
import com.shoo.app.components.LocalReduceMotion
import com.shoo.app.components.SfSymbol
import com.shoo.app.components.dynamicColor
import com.shoo.app.components.hex
import com.shoo.app.components.shooShadow
import com.shoo.app.components.shooSnappy
import com.shoo.app.support.L10n
import com.shoo.app.support.t

/** ON-02: avatar + name (D-alief-22). 1–20 characters, Next stays disabled until valid. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun NameView(model: OnboardingModel, modifier: Modifier = Modifier) {
    val view = LocalView.current
    val language = LocalAppLanguage.current
    val reduceMotion = LocalReduceMotion.current
    val focusRequester = remember { FocusRequester() }
    val formRequester = remember { BringIntoViewRequester() }
    var focused by remember { mutableStateOf(false) }
    // Figma "Atur Nama": no avatar is marked until the user picks one or starts typing.
    var pickedAvatar by remember { mutableStateOf(false) }

    // Nothing typed yet is not an error; spaces only or too long is.
    val visibleProblem: NameRule.Problem? = if (model.name.isEmpty()) null else model.nameProblem

    LaunchedEffect(visibleProblem) {
        val problem = visibleProblem ?: return@LaunchedEffect
        val key = if (problem == NameRule.Problem.Empty) "Enter your name." else "Use 20 characters or fewer."
        @Suppress("DEPRECATION")
        view.announceForAccessibility(L10n.string(key, language))
    }

    // `.sensoryFeedback(.selection, trigger: model.selectedAvatarId)`: not on first appearance.
    var lastAvatar by remember { mutableStateOf(model.selectedAvatarId) }
    LaunchedEffect(model.selectedAvatarId) {
        if (model.selectedAvatarId != lastAvatar) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        lastAvatar = model.selectedAvatarId
    }

    OnboardingFormPage(
        title = "Set up your profile",
        message = "Choose an avatar and enter your name!",
        onBack = model::goBack,
        modifier = modifier,
        scrollTarget = if (focused) formRequester else null,
        content = {
            Column(modifier = Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                // A new pick crossfades in place with a small settle (the picker's own snappy spring).
                AnimatedContent(
                    targetState = model.selectedAvatarId,
                    transitionSpec = {
                        if (reduceMotion) {
                            fadeIn(shooSnappy(0.25)) togetherWith fadeOut(shooSnappy(0.25))
                        } else {
                            (scaleIn(shooSnappy(0.25), initialScale = 0.9f) + fadeIn(shooSnappy(0.25))) togetherWith
                                (scaleOut(shooSnappy(0.25), targetScale = 0.9f) + fadeOut(shooSnappy(0.25)))
                        }
                    },
                    // Figma: message ends at y 182, avatar at 209, picker at 352, field at 464.
                    modifier = Modifier.padding(top = 27.dp).size(100.dp).clearAndSetSemantics { },
                    label = "avatar",
                ) { id ->
                    Image(
                        painter = painterResource(AvatarCatalog.memojiImage(id)),
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier.size(100.dp).border(3.dp, OnboardingTheme.card, CircleShape),
                    )
                }

                AvatarPicker(
                    selectedId = model.selectedAvatarId,
                    isMarked = pickedAvatar || model.name.isNotEmpty(),
                    onPick = { id ->
                        pickedAvatar = true
                        model.selectedAvatarId = id
                    },
                    modifier = Modifier.padding(top = 43.dp),
                )

                NameField(
                    model = model,
                    visibleProblem = visibleProblem,
                    focusRequester = focusRequester,
                    onFocusChange = { focused = it },
                    modifier = Modifier.padding(top = 32.dp).bringIntoViewRequester(formRequester),
                )
            }
        },
        footer = {
            OnboardingCapsuleButton(
                title = "Next",
                onClick = model::submitName,
                enabled = model.canSubmitName,
                identifier = "name.continue",
            )
        },
    )
}

/** Figma "Frame 8": four 80 pt avatars, 12 apart, 1 pt wider than the content on each side. */
@Composable
private fun AvatarPicker(selectedId: String, isMarked: Boolean, onPick: (String) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            // `.padding(.horizontal, -1)`.
            .layout { measurable, constraints ->
                val extra = 2.dp.roundToPx()
                val placeable = measurable.measure(
                    constraints.copy(
                        minWidth = constraints.minWidth + extra,
                        maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra else constraints.maxWidth,
                    ),
                )
                layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AvatarCatalog.memojiIds.forEachIndexed { index, id ->
            AvatarChoice(
                image = AvatarCatalog.memojiImage(id),
                number = index + 1,
                isSelected = selectedId == id,
                isMarked = isMarked,
                action = { onPick(id) },
                modifier = Modifier
                    .weight(1f, fill = false)
                    .semantics { testTag = "name.avatar.${index + 1}" },
            )
        }
    }
}

/** One 80 pt memoji (smaller on narrow screens); the chosen one gets Figma's 4 pt green frame and shadow. */
@Composable
private fun AvatarChoice(
    image: Int,
    number: Int,
    isSelected: Boolean,
    /** False until there is a pick to show (`isSelected` is still true for TalkBack). */
    isMarked: Boolean,
    action: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interaction = remember { MutableInteractionSource() }
    val label = t("Avatar %lld", number)
    val shows = isSelected && isMarked
    Image(
        painter = painterResource(image),
        contentDescription = null,
        contentScale = ContentScale.Fit,
        modifier = modifier
            .onboardingPress(interaction)
            .sizeIn(maxWidth = 80.dp, maxHeight = 80.dp)
            .aspectRatio(1f)
            // Figma: #000 3 %, y 12, blur 6.
            .shooShadow(Color.Black.copy(alpha = if (shows) 0.03f else 0f), radius = 3.dp, y = 12.dp, shape = CircleShape)
            .border(
                if (shows) 4.dp else 2.dp,
                if (shows) OnboardingTheme.avatarSelectedStroke else OnboardingTheme.card,
                CircleShape,
            )
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = action)
            .semantics {
                contentDescription = label
                selected = isSelected
            },
    )
}

@Composable
private fun NameField(
    model: OnboardingModel,
    visibleProblem: NameRule.Problem?,
    focusRequester: FocusRequester,
    onFocusChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = OnboardingTheme.ink
    val placeholder = OnboardingTheme.placeholder
    val red = dynamicColor(0xFF3B30, 0xFF453A)
    val shape = RoundedCornerShape(16.dp)
    // Figma "SF Pro Text Regular 17", -2 %.
    val fieldStyle = onboardingFont(17f, tracking = -0.34f, family = FigmaFont.Family.TEXT)
    val clearLabel = t("Clear name")

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                // Figma "row": #784650 4%, y 1, blur 2.
                .shooShadow(hex(0x784650, 0.04f), radius = 1.dp, y = 1.dp, shape = shape)
                .background(OnboardingTheme.card, shape)
                .border(1.dp, if (visibleProblem == NameRule.Problem.Empty) red else ink.copy(alpha = 0.25f), shape)
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    focusRequester.requestFocus()
                }
                .padding(start = 18.dp, end = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // iOS `.textContentType(.givenName)`: Android autofill hints are not set here.
            BasicTextField(
                value = model.name,
                onValueChange = { model.name = it },
                textStyle = fieldStyle.copy(color = ink),
                cursorBrush = SolidColor(ink),
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Words,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Next,
                ),
                keyboardActions = KeyboardActions(onNext = { model.submitName() }),
                modifier = Modifier
                    .weight(1f)
                    .padding(vertical = 16.dp)
                    .focusRequester(focusRequester)
                    .onFocusChanged { onFocusChange(it.isFocused) }
                    .semantics { testTag = "name.field" },
                decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (model.name.isEmpty()) {
                            Text(t("Write your name"), style = fieldStyle.copy(color = placeholder))
                        }
                        inner()
                    }
                },
            )

            if (model.name.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .sizeIn(minWidth = 44.dp, minHeight = 44.dp)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                        ) { model.name = "" }
                        .semantics { contentDescription = clearLabel },
                    contentAlignment = Alignment.Center,
                ) {
                    SfSymbol("xmark.circle.fill", pointSize = 17f, tint = placeholder)
                }
            }
        }

        // Figma "Atur Profilmu" (1205:4697): the limit is always shown as a plain note under the field; spaces only
        // is the one real error.
        if (visibleProblem == NameRule.Problem.Empty) {
            Row(
                modifier = Modifier.semantics(mergeDescendants = true) { testTag = "name.error" },
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SfSymbol("exclamationmark.circle.fill", pointSize = 13f, tint = red)
                Text(t("Enter your name."), style = onboardingFont(13f, rounded = true).copy(color = red))
            }
        } else {
            Text(
                t("*Your name can be up to 20 characters"),
                // Figma "Atur Nama · nama terlalu panjang": still the plain note, no red.
                style = onboardingFont(13f, rounded = true, tracking = -0.08f)
                    .copy(color = OnboardingTheme.noteInk.copy(alpha = OnboardingTheme.noteInk.alpha * 0.7f)),
                modifier = Modifier.semantics {
                    testTag = if (visibleProblem == NameRule.Problem.TooLong) "name.error" else "name.note"
                },
            )
        }
    }
}
