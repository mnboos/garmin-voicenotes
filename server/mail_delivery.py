"""Send recording attachments through an SMTP relay over TLS."""

from contextlib import suppress
from dataclasses import dataclass
from email.errors import HeaderParseError
from email.headerregistry import Address
from email.message import EmailMessage
import smtplib
import ssl


@dataclass(frozen=True)
class MailDelivery:
    host: str
    port: int
    mode: str
    sender: str
    recipient: str
    username: str
    password: str

    @classmethod
    def from_environment(cls, environment):
        host = environment.get("VOICENOTES_SMTP_HOST", "").strip()
        recipient = environment.get("VOICENOTES_EMAIL_TO", "").strip()
        sender = environment.get("VOICENOTES_EMAIL_FROM", "").strip()
        username = environment.get("VOICENOTES_SMTP_USER", "")
        password = environment.get("VOICENOTES_SMTP_PASSWORD", "")
        if not any((host, sender, recipient, username, password)):
            return None
        if not (host and sender and recipient):
            raise ValueError("Email needs VOICENOTES_SMTP_HOST, VOICENOTES_EMAIL_FROM and VOICENOTES_EMAIL_TO")
        if bool(username) != bool(password):
            raise ValueError("Set both VOICENOTES_SMTP_USER and VOICENOTES_SMTP_PASSWORD to authenticate")
        try:
            for mailbox in (sender, recipient):
                address = Address(addr_spec=mailbox)
                if not address.username or not address.domain or not mailbox.isascii():
                    raise ValueError
        except (ValueError, HeaderParseError):
            raise ValueError("Email sender and recipient must each be a single ASCII email address") from None
        mode = environment.get("VOICENOTES_SMTP_TLS", "starttls").strip().lower()
        if mode not in ("starttls", "implicit"):
            raise ValueError("VOICENOTES_SMTP_TLS must be starttls or implicit")
        try:
            port = int(environment.get("VOICENOTES_SMTP_PORT", "587" if mode == "starttls" else "465"))
            if not 1 <= port <= 65535:
                raise ValueError
        except ValueError:
            raise ValueError("VOICENOTES_SMTP_PORT must be between 1 and 65535") from None
        return cls(host, port, mode, sender, recipient, username, password)

    def send(self, note_id, extension, digest, audio):
        message = EmailMessage()
        message["From"] = self.sender
        message["To"] = self.recipient
        message["Subject"] = f"Voicenotes recording {note_id}"
        domain = Address(addr_spec=self.sender).domain
        message["Message-ID"] = f"<voicenotes.{note_id}.{digest}@{domain}>"
        message.set_content("Your Voicenotes recording is attached.")
        message.add_attachment(audio, maintype="audio", subtype=extension, filename=f"{note_id}.{extension}")
        context = ssl.create_default_context()
        if self.mode == "implicit":
            client = smtplib.SMTP_SSL(self.host, self.port, timeout=15, context=context)
        else:
            client = smtplib.SMTP(self.host, self.port, timeout=15)
        try:
            if self.mode == "starttls":
                client.starttls(context=context)
            if self.username:
                client.login(self.username, self.password)
            client.send_message(message, from_addr=self.sender, to_addrs=[self.recipient])
        finally:
            # A failed QUIT after an accepted message must not queue another delivery.
            with suppress(OSError):
                client.close()
