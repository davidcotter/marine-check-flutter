defmodule DipguideBackend.Accounts.UserNotifier do
  import Swoosh.Email

  alias DipguideBackend.Mailer
  alias DipguideBackend.Accounts.User

  @from_name "DipGuide"

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, text_body, html_body) do
    from_email = System.get_env("MAIL_FROM", "noreply@dipreport.com")

    email =
      new()
      |> to(recipient)
      |> from({@from_name, from_email})
      |> reply_to({@from_name, from_email})
      |> subject(subject)
      |> text_body(text_body)
      |> html_body(html_body)
      |> header("X-Mailer", "DipGuide/1.0")
      |> header("X-Priority", "3")

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp email_template(title, greeting, message, button_text, button_url, footer) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{title}</title>
    </head>
    <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f4f4f5;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f4f4f5; padding: 40px 20px;">
        <tr>
          <td align="center">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width: 480px; background-color: #ffffff; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.05);">
              <!-- Header -->
              <tr>
                <td style="padding: 32px 32px 24px; text-align: center; border-bottom: 1px solid #e4e4e7;">
                  <div style="font-size: 28px; margin-bottom: 8px;">🌊</div>
                  <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #0f172a;">DipGuide</h1>
                  <p style="margin: 4px 0 0; font-size: 13px; color: #64748b;">Marine Forecasts for Sea Swimmers</p>
                </td>
              </tr>
              <!-- Content -->
              <tr>
                <td style="padding: 32px;">
                  <p style="margin: 0 0 16px; font-size: 16px; color: #374151;">#{greeting}</p>
                  <p style="margin: 0 0 24px; font-size: 15px; color: #4b5563; line-height: 1.6;">#{message}</p>
                  <!-- Button -->
                  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                    <tr>
                      <td align="center" style="padding: 8px 0 24px;">
                        <a href="#{button_url}" style="display: inline-block; padding: 14px 32px; background-color: #2563eb; color: #ffffff; text-decoration: none; font-weight: 600; font-size: 15px; border-radius: 8px;">#{button_text}</a>
                      </td>
                    </tr>
                  </table>
                  <p style="margin: 0; font-size: 13px; color: #9ca3af; line-height: 1.5;">#{footer}</p>
                  <!-- Fallback link -->
                  <p style="margin: 24px 0 0; padding-top: 16px; border-top: 1px solid #e4e4e7; font-size: 12px; color: #9ca3af;">
                    If the button doesn't work, copy and paste this link:<br>
                    <a href="#{button_url}" style="color: #2563eb; word-break: break-all;">#{button_url}</a>
                  </p>
                </td>
              </tr>
              <!-- Footer -->
              <tr>
                <td style="padding: 24px 32px; background-color: #f8fafc; border-radius: 0 0 12px 12px; text-align: center;">
                  <p style="margin: 0; font-size: 12px; color: #9ca3af;">
                    © #{DateTime.utc_now().year} DipGuide · <a href="https://dipreport.com" style="color: #64748b;">dipreport.com</a>
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    text = """
    Hi #{user.email},

    You requested to change your email address. Click the link below to confirm:

    #{url}

    If you didn't request this change, please ignore this email.

    - The DipGuide Team
    """

    html =
      email_template(
        "Update Your Email",
        "Hi there! 👋",
        "You requested to change your email address. Click the button below to confirm the change.",
        "Confirm Email Change",
        url,
        "If you didn't request this change, you can safely ignore this email."
      )

    deliver(user.email, "DipGuide - Confirm Your Email Change", text, html)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    text = """
    Hi #{user.email},

    Click the link below to log into DipGuide:

    #{url}

    This link expires in 15 minutes.

    If you didn't request this, please ignore this email.

    - The DipGuide Team
    """

    html =
      email_template(
        "Log In to DipGuide",
        "Welcome back! 👋",
        "Click the button below to securely log into your DipGuide account. This link expires in 15 minutes.",
        "Log In to DipGuide",
        url,
        "If you didn't request this login link, you can safely ignore this email."
      )

    deliver(user.email, "DipGuide - Your Login Link", text, html)
  end

  defp deliver_confirmation_instructions(user, url) do
    text = """
    Hi #{user.email},

    Welcome to DipGuide! Click the link below to confirm your account:

    #{url}

    This link expires in 15 minutes.

    If you didn't sign up, please ignore this email.

    - The DipGuide Team
    """

    html =
      email_template(
        "Welcome to DipGuide",
        "Welcome to DipGuide! 🌊",
        "Thanks for signing up! Click the button below to confirm your account and start checking marine forecasts.",
        "Confirm My Account",
        url,
        "If you didn't create an account, you can safely ignore this email."
      )

    deliver(user.email, "DipGuide - Confirm Your Account", text, html)
  end
end
