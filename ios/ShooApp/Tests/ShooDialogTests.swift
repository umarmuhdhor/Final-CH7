import Testing
@testable import Shoo

struct ShooDialogTests {
    @Test(arguments: [
        ("Couldn't save. Check your connection and try again.", "Couldn't save", "Check your connection and try again."),
        ("Gagal menyimpan. Periksa koneksi lalu coba lagi.", "Gagal menyimpan", "Periksa koneksi lalu coba lagi."),
        ("Reminder failed", "Reminder failed", nil),
        ("Couldn't save. ", "Couldn't save", nil),
    ] as [(String, String, String?)])
    func errorSplitsIntoTitleAndDetail(message: String, title: String, detail: String?) {
        let parts = ShooDialog.errorParts(message)
        #expect(parts.title == title)
        #expect(parts.detail == detail)
    }

    @Test func errorDialogIsOneOKWithTheSorryPose() {
        let dialog = ShooDialog.error("Couldn't save. Check your connection and try again.")
        #expect(dialog.pose == .sorry)
        #expect(dialog.secondary == nil)
        #expect(dialog.primary.identifier == "shooDialog.ok")
    }
}
