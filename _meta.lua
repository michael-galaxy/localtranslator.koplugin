local _ = require("gettext")
return {
    name = "localtranslator",
    fullname = _("Local Translator"),
    description = _([[Translate selected text by sending it to another Android app (e.g. a translator app) via Intent. No network required. Configure the target app package in settings.]]),
    author = "KOReader Community",
    version = "1.1.1",
}
