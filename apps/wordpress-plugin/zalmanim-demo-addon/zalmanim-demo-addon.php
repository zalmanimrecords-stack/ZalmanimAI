<?php
/**
 * Plugin Name: Zalmanim Demo Addon
 * Description: Renders a configurable demo submission form and forwards it to LabelOps.
 * Version: 0.1.0
 * Author: Codex
 */

if (!defined('ABSPATH')) {
    exit;
}

final class Zalmanim_Demo_Addon {
    private const OPTION_KEY = 'zalmanim_demo_addon_options';
    private const SHORTCODE = 'zalmanim_demo_form';

    public function __construct() {
        add_action('admin_menu', [$this, 'register_admin_page']);
        add_action('admin_init', [$this, 'register_settings']);
        add_shortcode(self::SHORTCODE, [$this, 'render_shortcode']);
        add_action('wp_ajax_zalmanim_demo_submit', [$this, 'ajax_submit']);
        add_action('wp_ajax_nopriv_zalmanim_demo_submit', [$this, 'ajax_submit']);
    }

    public function register_admin_page(): void {
        add_options_page(
            'Zalmanim Demo Addon',
            'Zalmanim Demo Addon',
            'manage_options',
            'zalmanim-demo-addon',
            [$this, 'render_admin_page']
        );
    }

    public function register_settings(): void {
        register_setting(
            'zalmanim_demo_addon_group',
            self::OPTION_KEY,
            [
                'type' => 'array',
                'sanitize_callback' => [$this, 'sanitize_options'],
                'default' => $this->default_options(),
            ]
        );
    }

    public function sanitize_options($input): array {
        $defaults = $this->default_options();
        $output = is_array($input) ? $input : [];
        return [
            'api_endpoint' => esc_url_raw($output['api_endpoint'] ?? $defaults['api_endpoint']),
            'api_token' => sanitize_text_field($output['api_token'] ?? ''),
            'success_message' => sanitize_text_field($output['success_message'] ?? $defaults['success_message']),
            'submit_label' => sanitize_text_field($output['submit_label'] ?? $defaults['submit_label']),
            'form_schema_json' => is_string($output['form_schema_json'] ?? null) ? $output['form_schema_json'] : $defaults['form_schema_json'],
        ];
    }

    private function default_options(): array {
        return [
            'api_endpoint' => 'https://lmapi.zalmanim.com/api/public/demo-submissions',
            'api_token' => 'TOKEN',
            'success_message' => 'Thanks, your demo was sent successfully.',
            'submit_label' => 'Send Demo',
            'form_schema_json' => wp_json_encode($this->default_schema(), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES),
        ];
    }

    private function get_options(): array {
        $options = get_option(self::OPTION_KEY, []);
        return wp_parse_args(is_array($options) ? $options : [], $this->default_options());
    }

    private function default_schema(): array {
        return [
            ['name' => 'artist_name', 'label' => 'Artist Name', 'type' => 'text', 'required' => true, 'role' => 'artist_name'],
            ['name' => 'contact_name', 'label' => 'Contact Name', 'type' => 'text', 'required' => false, 'role' => 'contact_name'],
            ['name' => 'email', 'label' => 'Email', 'type' => 'email', 'required' => true, 'role' => 'email'],
            ['name' => 'phone', 'label' => 'Phone', 'type' => 'text', 'required' => false, 'role' => 'phone'],
            ['name' => 'genre', 'label' => 'Musical Style', 'type' => 'select', 'required' => false, 'role' => 'genre', 'options' => $this->genre_options()],
            ['name' => 'city', 'label' => 'City', 'type' => 'text', 'required' => false, 'role' => 'city'],
            ['name' => 'soundcloud', 'label' => 'SoundCloud Link', 'type' => 'url', 'required' => false, 'role' => 'link'],
            ['name' => 'spotify', 'label' => 'Artist Page on Spotify', 'type' => 'url', 'required' => false, 'role' => 'link'],
            ['name' => 'message', 'label' => 'Message', 'type' => 'textarea', 'required' => false, 'role' => 'message'],
        ];
    }

    private function genre_options(): array {
        return [
            'House',
            'House / Acid',
            'House / Soulful',
            'Jackin House',
            'Organic House',
            'Progressive House',
            'Afro House',
            'Afro House / Afro Latin',
            'Afro House / Afro Melodic',
            'Afro House / 3Step',
            'Tech House',
            'Tech House / Latin Tech',
            'Melodic House & Techno / Melodic House',
            'Hard Techno',
            'Techno (Peak Time / Driving)',
            'Techno / Peak Time',
            'Techno / Driving',
            'Techno / Psy-Techno',
            'Techno (Raw / Deep / Hypnotic)',
            'Techno / Raw',
            'Techno / Deep / Hypnotic',
            'Techno / Dub',
            'Techno / EBM',
            'Techno / Broken',
            'Melodic House & Techno / Melodic Techno',
            'Trance (Main Floor)',
            'Trance / Progressive Trance',
            'Trance / Tech Trance',
            'Trance / Uplifting Trance',
            'Trance / Vocal Trance',
            'Trance / Hard Trance',
            'Trance (Raw / Deep / Hypnotic)',
            'Trance / Raw Trance',
            'Trance / Deep Trance',
            'Trance / Hypnotic Trance',
            'Psy-Trance',
            'Psy-Trance / Full-On',
            'Psy-Trance / Progressive Psy',
            'Psy-Trance / Psychedelic',
            'Psy-Trance / Dark & Forest',
            'Psy-Trance / Goa Trance',
            'Psy-Trance / Psycore & Hi-Tech',
        ];
    }

    private function parse_schema(string $raw): array {
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) {
            return $this->default_schema();
        }
        $fields = [];
        foreach ($decoded as $field) {
            if (!is_array($field) || empty($field['name']) || empty($field['label'])) {
                continue;
            }
            $fields[] = [
                'name' => sanitize_key((string) $field['name']),
                'label' => sanitize_text_field((string) $field['label']),
                'type' => sanitize_key((string) ($field['type'] ?? 'text')),
                'required' => !empty($field['required']),
                'role' => sanitize_key((string) ($field['role'] ?? 'custom')),
                'options' => array_values(array_map('sanitize_text_field', is_array($field['options'] ?? null) ? $field['options'] : [])),
            ];
        }
        return !empty($fields) ? $fields : $this->default_schema();
    }

    public function render_admin_page(): void {
        $options = $this->get_options();
        ?>
        <div class="wrap">
            <h1>Zalmanim Demo Addon</h1>

            <div class="card" style="max-width: 720px; padding: 1em 1.5em; margin-bottom: 1.5em;">
                <h2 style="margin-top: 0;">How to use this plugin</h2>
                <ol style="margin-left: 1.2em;">
                    <li>Open the page where you want the form to appear.</li>
                    <li>Add a <strong>Shortcode</strong> block and paste <code>[<?php echo esc_html(self::SHORTCODE); ?>]</code>.</li>
                    <li>Save the page. The form will be rendered inside the page itself.</li>
                    <li>When a visitor submits the form, WordPress sends the data to the LM system endpoint configured below.</li>
                    <li>The submission is stored in the LM system as a demo submission with status <code>demo</code>.</li>
                </ol>
                <p style="margin-bottom: 0;">This plugin is for our internal production flow only. The defaults below are already set to production and the shared token is prefilled as <code>TOKEN</code>.</p>
            </div>

            <h2>Server and authentication</h2>
            <p>Choose which server receives the form data and which token is sent in the request header. For our system, keep the production endpoint and token unless explicitly changing infrastructure.</p>
            <form method="post" action="options.php">
                <?php settings_fields('zalmanim_demo_addon_group'); ?>
                <table class="form-table" role="presentation">
                    <tr>
                        <th scope="row"><label for="zalmanim-demo-api-endpoint">API endpoint</label></th>
                        <td>
                            <input id="zalmanim-demo-api-endpoint" class="regular-text" type="url" name="<?php echo esc_attr(self::OPTION_KEY); ?>[api_endpoint]" value="<?php echo esc_attr($options['api_endpoint']); ?>">
                            <p class="description">Production LM endpoint. By default this is <code>https://lmapi.zalmanim.com/api/public/demo-submissions</code>. Every form submission is sent to this address via POST.</p>
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="zalmanim-demo-api-token">Shared token (TOKEN)</label></th>
                        <td>
                            <input id="zalmanim-demo-api-token" class="regular-text" type="text" name="<?php echo esc_attr(self::OPTION_KEY); ?>[api_token]" value="<?php echo esc_attr($options['api_token']); ?>">
                            <p class="description">This value is sent in the <code>x-demo-token</code> header with every submission. The LM server is also configured with the same default value: <code>TOKEN</code>.</p>
                        </td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="zalmanim-demo-success">Success message</label></th>
                        <td><input id="zalmanim-demo-success" class="regular-text" type="text" name="<?php echo esc_attr(self::OPTION_KEY); ?>[success_message]" value="<?php echo esc_attr($options['success_message']); ?>"></td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="zalmanim-demo-submit">Submit label</label></th>
                        <td><input id="zalmanim-demo-submit" class="regular-text" type="text" name="<?php echo esc_attr(self::OPTION_KEY); ?>[submit_label]" value="<?php echo esc_attr($options['submit_label']); ?>"></td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="zalmanim-demo-schema">Form schema JSON</label></th>
                        <td>
                            <textarea id="zalmanim-demo-schema" class="large-text code" rows="18" name="<?php echo esc_attr(self::OPTION_KEY); ?>[form_schema_json]"><?php echo esc_textarea($options['form_schema_json']); ?></textarea>
                            <p class="description">Each field supports: name, label, type, required, role, options. Roles map the form values into the LM system. Use roles like <code>artist_name</code>, <code>email</code>, <code>contact_name</code>, <code>phone</code>, <code>genre</code>, <code>city</code>, <code>message</code>, and <code>link</code>.</p>
                        </td>
                    </tr>
                </table>
                <?php submit_button(); ?>
            </form>
        </div>
        <?php
    }

    public function render_shortcode(): string {
        $options = $this->get_options();
        $schema = $this->parse_schema((string) $options['form_schema_json']);
        $feedback = $this->handle_submission($schema, $options);
        $ajax_url = admin_url('admin-ajax.php');
        $ajax_nonce = wp_create_nonce('zalmanim_demo_ajax');
        ob_start();
        ?>
        <div class="zalmanim-demo-addon">
            <?php if (!empty($feedback['message'])) : ?>
                <div class="zalmanim-demo-feedback <?php echo !empty($feedback['success']) ? 'is-success' : 'is-error'; ?>">
                    <?php echo esc_html($feedback['message']); ?>
                </div>
            <?php endif; ?>
            <form method="post" class="zalmanim-demo-form" data-ajax-url="<?php echo esc_url($ajax_url); ?>" data-ajax-nonce="<?php echo esc_attr($ajax_nonce); ?>">
                <?php wp_nonce_field('zalmanim_demo_submit', 'zalmanim_demo_nonce'); ?>
                <input type="hidden" name="zalmanim_demo_submit" value="1">
                <input type="hidden" name="action" value="zalmanim_demo_submit">
                <?php foreach ($schema as $field) : ?>
                    <?php $this->render_field($field); ?>
                <?php endforeach; ?>
                <button type="submit"><?php echo esc_html($options['submit_label']); ?></button>
            </form>
        </div>
        <style>
            .zalmanim-demo-form { display:grid; gap:16px; max-width:720px; }
            .zalmanim-demo-form label { display:block; font-weight:600; margin-bottom:6px; }
            .zalmanim-demo-form input,
            .zalmanim-demo-form textarea,
            .zalmanim-demo-form select { width:100%; padding:12px; border:1px solid #c7ccd1; border-radius:8px; }
            .zalmanim-demo-form button { width:max-content; padding:12px 20px; border:0; border-radius:999px; background:#111827; color:#fff; cursor:pointer; }
            .zalmanim-demo-feedback { margin-bottom:16px; padding:12px 14px; border-radius:8px; }
            .zalmanim-demo-feedback.is-success { background:#e8f7ee; color:#155724; }
            .zalmanim-demo-feedback.is-error { background:#fdecec; color:#8a1f1f; }
        </style>
        <script>
            (function() {
                var root = document.currentScript ? document.currentScript.parentNode : null;
                var form = root ? root.querySelector('.zalmanim-demo-form') : document.querySelector('.zalmanim-demo-form');
                if (!form) return;
                form.addEventListener('submit', function(event) {
                    event.preventDefault();
                    var button = form.querySelector('button[type="submit"]');
                    var formData = new FormData(form);
                    formData.append('security', form.getAttribute('data-ajax-nonce'));
                    if (button) {
                        button.disabled = true;
                    }
                    fetch(form.getAttribute('data-ajax-url'), {
                        method: 'POST',
                        body: formData,
                        credentials: 'same-origin'
                    })
                    .then(function(response) { return response.json(); })
                    .then(function(payload) {
                        var box = form.parentNode.querySelector('.zalmanim-demo-feedback');
                        if (!box) {
                            box = document.createElement('div');
                            box.className = 'zalmanim-demo-feedback';
                            form.parentNode.insertBefore(box, form);
                        }
                        var data = payload && payload.data ? payload.data : {};
                        box.textContent = data.message || 'Submission failed.';
                        box.className = 'zalmanim-demo-feedback ' + (payload.success ? 'is-success' : 'is-error');
                        if (payload.success) {
                            form.reset();
                        }
                    })
                    .catch(function() {
                        var box = form.parentNode.querySelector('.zalmanim-demo-feedback');
                        if (!box) {
                            box = document.createElement('div');
                            box.className = 'zalmanim-demo-feedback is-error';
                            form.parentNode.insertBefore(box, form);
                        }
                        box.textContent = 'Could not send the form right now.';
                        box.className = 'zalmanim-demo-feedback is-error';
                    })
                    .finally(function() {
                        if (button) {
                            button.disabled = false;
                        }
                    });
                });
            })();
        </script>
        <?php
        return (string) ob_get_clean();
    }

    public function ajax_submit(): void {
        check_ajax_referer('zalmanim_demo_ajax', 'security');
        $options = $this->get_options();
        $schema = $this->parse_schema((string) $options['form_schema_json']);
        $payload = $this->build_payload($schema);
        if (empty($payload['artist_name']) || empty($payload['email'])) {
            wp_send_json_error(['message' => 'Artist name and email are required.'], 400);
        }
        $result = $this->send_payload_to_lm($payload, $options);
        if (!empty($result['success'])) {
            wp_send_json_success(['message' => $result['message']]);
        }
        wp_send_json_error(['message' => $result['message']], 400);
    }

    private function render_field(array $field): void {
        $name = $field['name'];
        $label = $field['label'];
        $required = !empty($field['required']);
        $type = $field['type'];
        $value = isset($_POST[$name]) ? wp_unslash((string) $_POST[$name]) : '';
        ?>
        <div>
            <label for="<?php echo esc_attr($name); ?>">
                <?php echo esc_html($label); ?><?php echo $required ? ' *' : ''; ?>
            </label>
            <?php if ($type === 'textarea') : ?>
                <textarea id="<?php echo esc_attr($name); ?>" name="<?php echo esc_attr($name); ?>" <?php echo $required ? 'required' : ''; ?>><?php echo esc_textarea($value); ?></textarea>
            <?php elseif ($type === 'select') : ?>
                <select id="<?php echo esc_attr($name); ?>" name="<?php echo esc_attr($name); ?>" <?php echo $required ? 'required' : ''; ?>>
                    <option value="">Select</option>
                    <?php foreach ($field['options'] as $option) : ?>
                        <option value="<?php echo esc_attr($option); ?>" <?php selected($value, $option); ?>><?php echo esc_html($option); ?></option>
                    <?php endforeach; ?>
                </select>
            <?php else : ?>
                <input id="<?php echo esc_attr($name); ?>" type="<?php echo esc_attr($type); ?>" name="<?php echo esc_attr($name); ?>" value="<?php echo esc_attr($value); ?>" <?php echo $required ? 'required' : ''; ?>>
            <?php endif; ?>
        </div>
        <?php
    }

    private function handle_submission(array $schema, array $options): array {
        if ($_SERVER['REQUEST_METHOD'] !== 'POST' || empty($_POST['zalmanim_demo_submit'])) {
            return [];
        }
        if (!isset($_POST['zalmanim_demo_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['zalmanim_demo_nonce'])), 'zalmanim_demo_submit')) {
            return ['success' => false, 'message' => 'Security check failed. Please try again.'];
        }
        $payload = $this->build_payload($schema);
        if (empty($payload['artist_name']) || empty($payload['email'])) {
            return ['success' => false, 'message' => 'Artist name and email are required.'];
        }
        return $this->send_payload_to_lm($payload, $options);
    }

    private function send_payload_to_lm(array $payload, array $options): array {
        $args = [
            'headers' => array_filter([
                'Content-Type' => 'application/json',
                'x-demo-token' => $options['api_token'],
            ]),
            'body' => wp_json_encode($payload),
            'timeout' => 20,
        ];
        $response = wp_remote_post($options['api_endpoint'], $args);
        if (is_wp_error($response)) {
            return ['success' => false, 'message' => $response->get_error_message()];
        }
        $code = (int) wp_remote_retrieve_response_code($response);
        if ($code < 200 || $code >= 300) {
            $body = (string) wp_remote_retrieve_body($response);
            $decoded = json_decode($body, true);
            $message = is_array($decoded) && !empty($decoded['detail']) ? (string) $decoded['detail'] : 'Submission failed.';
            return ['success' => false, 'message' => $message];
        }
        return ['success' => true, 'message' => $options['success_message']];
    }

    private function build_payload(array $schema): array {
        $fields = [];
        $links = [];
        $payload = [
            'artist_name' => '',
            'contact_name' => '',
            'email' => '',
            'phone' => '',
            'genre' => '',
            'city' => '',
            'message' => '',
            'links' => [],
            'fields' => [],
            'source' => 'wordpress_demo_form',
            'source_site_url' => home_url('/'),
        ];
        foreach ($schema as $field) {
            $name = $field['name'];
            $value = isset($_POST[$name]) ? trim(wp_unslash((string) $_POST[$name])) : '';
            $fields[$name] = $value;
            switch ($field['role']) {
                case 'artist_name':
                    $payload['artist_name'] = $value;
                    break;
                case 'contact_name':
                    $payload['contact_name'] = $value;
                    break;
                case 'email':
                    $payload['email'] = $value;
                    break;
                case 'phone':
                    $payload['phone'] = $value;
                    break;
                case 'genre':
                    $payload['genre'] = $value;
                    break;
                case 'city':
                    $payload['city'] = $value;
                    break;
                case 'message':
                    $payload['message'] = $value;
                    break;
                case 'link':
                    if ($value !== '') {
                        $links[] = $value;
                    }
                    break;
            }
        }
        $payload['links'] = $links;
        $payload['fields'] = $fields;
        return $payload;
    }
}

new Zalmanim_Demo_Addon();
