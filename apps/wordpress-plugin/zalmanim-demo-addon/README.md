# Zalmanim Demo Addon

WordPress plugin that shows a configurable demo submission form and sends submissions to a Zalmanim LabelOps API.

## Where to Place the Form

The form is inserted via **shortcode**. Add it to any page or post:

- **Shortcode:** `[zalmanim_demo_form]`

**How to use:**

1. Create or edit a **Page** or **Post** in WordPress.
2. In the editor, add a **Shortcode** block (or type the shortcode in a Paragraph block).
3. Enter: `[zalmanim_demo_form]`
4. Publish or update. The demo form will appear where you placed the shortcode.

You can use the shortcode on multiple pages if needed. The same form and settings apply everywhere.

## Choosing the Server and Token

Submissions are sent to the **API endpoint** you configure, with the **Shared token** in the request headers.

### 1. Open settings

In WordPress admin: **Settings → Zalmanim Demo Addon**.

### 2. API endpoint (which server receives the data)

- **Field:** **API endpoint**
- Set the full URL of your Zalmanim server’s demo-submissions API.
- Examples:
  - Local: `http://localhost:8000/api/public/demo-submissions`
  - Production: `https://your-zalmanim-server.com/api/public/demo-submissions`
- All form submissions are sent to this URL via HTTP POST.

### 3. Shared token (TOKEN)

- **Field:** **Shared token**
- This value is sent in the **`x-demo-token`** header with every submission.
- The server uses it to accept or reject submissions. You must configure the **same token** on the Zalmanim server (LabelOps) as the allowed demo token.
- Leave empty only if your server does not require a token (not recommended for production).

**Summary:** Set **API endpoint** to the server that should receive the data, and **Shared token** to the TOKEN that server expects in the `x-demo-token` header.

## Other Settings

- **Success message** – Text shown after a successful submission.
- **Submit label** – Label of the submit button.
- **Form schema JSON** – Defines form fields (name, label, type, required, role). Edit only if you need to change which fields appear and how they map to the API.

## Requirements

- WordPress 5.0+
- The target server must expose the demo-submissions endpoint and accept the `x-demo-token` header you configure.
