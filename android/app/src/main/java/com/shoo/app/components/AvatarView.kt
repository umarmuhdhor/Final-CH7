package com.shoo.app.components

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.shoo.app.R

/**
 * The 12 avatars `avatar_01…avatar_12` (D-alief-13). `avatar_01…04` are the ON-02 bird avatars the user can pick
 * (#120), drawn as the Memoji images; the rest are placeholders for the server's random pick.
 */
object AvatarCatalog {
    /** `color` is an iOS system colour (light value): the catalog is drawn the same in both themes. */
    data class Avatar(val symbol: String, val color: Color)

    val ids: List<String> = (1..12).map { "avatar_%02d".format(it) }

    private val avatars: List<Avatar> = listOf(
        Avatar("hare.fill", hex(0xFF9500)), // orange
        Avatar("tortoise.fill", hex(0x34C759)), // green
        Avatar("bird.fill", hex(0x007AFF)), // blue
        Avatar("fish.fill", hex(0x30B0C7)), // teal
        Avatar("pawprint.fill", hex(0xA2845E)), // brown
        Avatar("ant.fill", hex(0xFF3B30)), // red
        Avatar("ladybug.fill", hex(0xFF2D55)), // pink
        Avatar("leaf.fill", hex(0x00C7BE)), // mint
        Avatar("star.fill", hex(0xFFCC00)), // yellow
        Avatar("moon.fill", hex(0x5856D6)), // indigo
        Avatar("sun.max.fill", hex(0xFF9500)), // orange
        Avatar("cloud.fill", hex(0x32ADE6)), // cyan
    )

    val fallback = Avatar("person.fill", hex(0x8E8E93))

    fun avatar(id: String): Avatar {
        val index = ids.indexOf(id)
        return if (index < 0) fallback else avatars[index]
    }

    /** The ON-02 picker avatars (`OnboardingAvatar.ids` in NameView). */
    val memojiIds: List<String> = listOf("avatar_01", "avatar_02", "avatar_03", "avatar_04")

    private val memojis = intArrayOf(R.drawable.memoji01, R.drawable.memoji02, R.drawable.memoji03, R.drawable.memoji04)

    /** iOS `OnboardingAvatar.imageName(for:)`: the memoji for a picker id, the first one for any other id. */
    @DrawableRes
    fun memojiImage(id: String): Int = memojis[memojiIds.indexOf(id).coerceAtLeast(0)]

    /** iOS `OnboardingAvatar.memoji(for:)`: the memoji drawable for a picker id, null for the rest of the catalog. */
    @DrawableRes
    fun memoji(id: String): Int? = memojiIds.indexOf(id).takeIf { it >= 0 }?.let { memojis[it] }
}

/** `AvatarView.Ring`: a rim on the avatar's edge (Figma's white rings on Home, in stacks and on badges). */
data class AvatarRing(val color: Color = Color.White, val width: Dp = 1.dp)

/**
 * The picked memoji, or a coloured circle with the avatar's symbol. Decorative unless a name is given.
 * An unknown or empty id draws `AvatarCatalog.fallback` (a grey person).
 */
@Composable
fun AvatarView(
    id: String,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    name: String? = null,
    ring: AvatarRing? = null,
) {
    val semantics = if (name == null) {
        Modifier.clearAndSetSemantics { }
    } else {
        Modifier.clearAndSetSemantics { contentDescription = name }
    }
    Box(
        modifier
            .size(size)
            .then(semantics),
        contentAlignment = Alignment.Center,
    ) {
        val memoji = AvatarCatalog.memoji(id)
        if (memoji != null) {
            Image(
                painter = painterResource(memoji),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clip(CircleShape),
            )
        } else {
            val avatar = AvatarCatalog.avatar(id)
            Icon(
                imageVector = sfSymbol(avatar.symbol),
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier
                    .fillMaxSize()
                    .background(avatar.color.swiftGradient(), CircleShape)
                    .padding(size * 0.24f),
            )
        }
        // iOS: the stroke is centred on the edge; here it sits inside it.
        if (ring != null) {
            Box(Modifier.fillMaxSize().border(ring.width, ring.color, CircleShape))
        }
    }
}

/** SwiftUI `Color.gradient`: the colour, a little lighter at the top to a little darker at the bottom. */
private fun Color.swiftGradient(): Brush = Brush.verticalGradient(
    listOf(lerp(this, Color.White, 0.12f), lerp(this, Color.Black, 0.06f)),
)
