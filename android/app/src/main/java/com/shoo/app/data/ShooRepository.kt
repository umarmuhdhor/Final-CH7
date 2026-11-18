package com.shoo.app.data

/**
 * Every backend operation the app uses, shaped by contracts/api.md.
 * `MockRepository` (fixtures) and `ApiRepository` (the backend): views never change.
 * Errors: `RepositoryError`; a cancelled call throws `CancellationException`.
 */
interface ShooRepository {
    /** `POST /devices` (ON-02, ON-03). `avatarId` is the ON-02 pick; null or unknown → the server picks (#120). */
    suspend fun registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?): DeviceRegistration

    /** `GET /devices/me` (PR-04, PF-01). */
    suspend fun me(): DeviceProfile

    /** `PATCH /devices/me` (ON-05, PF-01, GD-03). */
    suspend fun updateMe(update: DeviceUpdate)

    /** `POST /family/code` — guardian (GD-04). The active code while it has more than 5 min left;
     * `refresh` always makes a new one and the old one stops working. */
    suspend fun createFamilyCode(refresh: Boolean): FamilyCode

    /** `POST /family/join` — protected (PR-01, PR-03). */
    suspend fun joinFamily(code: String): GuardianInfo

    /** `GET /family/members` — guardian (GD-03). */
    suspend fun familyMembers(): List<FamilyMember>

    /** `DELETE /family/members/{deviceId}` — guardian (GD-04). */
    suspend fun removeMember(deviceId: String)

    /** `PATCH /family/members/{deviceId} { notify }` — guardian, "Kabari saya" (PF-01 proposed). */
    suspend fun setMemberNotify(deviceId: String, notify: Boolean)

    /** `POST /family/members/{deviceId}/remind` — guardian, "Ingatkan" (PF-01 proposed).
     * Throws `push_unavailable` (member has notifications off) or `remind_too_soon` (within 6 h). */
    suspend fun remindMember(deviceId: String)

    /** `DELETE /family/guardian` — protected (PF-01). */
    suspend fun leaveGuardian()

    /** `POST /devices/me/protected` (PF-01 proposed, "Punya kode undangan?"): a guardian without members joins a
     * family as protected. The server makes a new protected device, joins it and deletes this one; the caller saves
     * the new session. Join errors as `joinFamily`, plus `has_members`. */
    suspend fun becomeProtected(code: String): ProtectedSwitch

    /** `DELETE /devices/me` (PF-01, SECURITY §3 P3): removes the device and everything about it (family links,
     * codes, scans + screenshots, verdicts). The token stops working. */
    suspend fun deleteMe()

    /** `GET /scans` newest first (PR-05, GD-05). `screenshotUrl` is always null in lists. */
    suspend fun scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?): ScanPage

    /** `GET /scans/{id}` (DT-*). */
    suspend fun scan(id: String): ScanResult

    /** `POST /verdicts` — guardian (GD-07). */
    suspend fun setVerdict(scanId: String, value: Verdict.Value): Verdict

    /** `POST /verdicts` with `notes` (≤ 280 characters): why the Guardian decided. Team AI learns from it (#241).
     * Test doubles without notes: the verdict goes through, the note is not recorded. */
    suspend fun setVerdict(scanId: String, value: Verdict.Value, notes: String?): Verdict = setVerdict(scanId, value)

    /** `GET /scams/latest`: the Home card "Scam terbaru di pengguna Shoo" (contracts/api.md, PR-04, GD-01).
     * Empty = no card. Test doubles: no card. */
    suspend fun latestScams(): List<ScamCase> = emptyList()
}
