<?php
/**
 * Plugin Name: Zalmanim Artists
 * Description: Displays artists with Linktree links, label releases list, and the demo submission form from the portal. Data is fetched from the Zalmanim API.
 * Version: 1.1.0
 * Author: Zalmanim
 * Text Domain: zalmanim-artists
 * Requires at least: 5.9
 * Requires PHP: 7.4
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

define( 'ZALMANIM_ARTISTS_VERSION', '1.1.0' );
define( 'ZALMANIM_ARTISTS_CACHE_KEY', 'zalmanim_artists_list' );
define( 'ZALMANIM_ARTISTS_RELEASES_CACHE_KEY', 'zalmanim_releases_list' );
define( 'ZALMANIM_ARTISTS_CACHE_TTL', 15 * MINUTE_IN_SECONDS ); // 15 minutes

/**
 * Get plugin option: API base URL (no trailing slash).
 *
 * @return string
 */
function zalmanim_artists_get_api_base() {
	return trim( (string) get_option( 'zalmanim_artists_api_base', '' ) );
}

/**
 * Get plugin option: Public linktree base URL for artists without Linktree (e.g. https://artists.example.com/linktree). Optional.
 *
 * @return string
 */
function zalmanim_artists_get_linktree_base() {
	return trim( (string) get_option( 'zalmanim_artists_linktree_base', '' ) );
}

/**
 * Get plugin option: Artist portal base URL (for embedding demo form as iframe). Optional.
 *
 * @return string
 */
function zalmanim_artists_get_portal_url() {
	return trim( (string) get_option( 'zalmanim_artists_portal_url', '' ) );
}

/**
 * Get plugin option: Demo submission token (sent to API when submitting demo form). Optional if API does not require it.
 *
 * @return string
 */
function zalmanim_artists_get_demo_token() {
	return trim( (string) get_option( 'zalmanim_artists_demo_token', '' ) );
}

/**
 * Fetch artists from API. Uses transient cache.
 *
 * @return array{artist_id: int, name: string, linktree_url: string|null}[]
 */
function zalmanim_artists_fetch() {
	$cached = get_transient( ZALMANIM_ARTISTS_CACHE_KEY );
	if ( is_array( $cached ) ) {
		return $cached;
	}

	$api_base = zalmanim_artists_get_api_base();
	if ( $api_base === '' ) {
		return array();
	}

	$url = rtrim( $api_base, '/' ) . '/public/artists-with-releases?limit=500';
	$response = wp_remote_get( $url, array(
		'timeout' => 15,
		'headers' => array( 'Accept' => 'application/json' ),
	) );

	if ( is_wp_error( $response ) ) {
		return array();
	}

	$code = wp_remote_retrieve_response_code( $response );
	if ( $code !== 200 ) {
		return array();
	}

	$body = wp_remote_retrieve_body( $response );
	$data = json_decode( $body, true );
	if ( ! is_array( $data ) ) {
		return array();
	}

	// Normalize: ensure each item has artist_id, name, linktree_url
	$list = array();
	foreach ( $data as $item ) {
		if ( ! is_array( $item ) || ! isset( $item['artist_id'], $item['name'] ) ) {
			continue;
		}
		$list[] = array(
			'artist_id'    => (int) $item['artist_id'],
			'name'         => sanitize_text_field( $item['name'] ),
			'linktree_url' => isset( $item['linktree_url'] ) && is_string( $item['linktree_url'] ) && $item['linktree_url'] !== ''
				? esc_url_raw( $item['linktree_url'] )
				: null,
		);
	}

	set_transient( ZALMANIM_ARTISTS_CACHE_KEY, $list, ZALMANIM_ARTISTS_CACHE_TTL );
	return $list;
}

/**
 * Fetch releases from API. Uses transient cache.
 *
 * @return array{id: int, title: string, artist_names: string[], created_at: string}[]
 */
function zalmanim_releases_fetch() {
	$cached = get_transient( ZALMANIM_ARTISTS_RELEASES_CACHE_KEY );
	if ( is_array( $cached ) ) {
		return $cached;
	}

	$api_base = zalmanim_artists_get_api_base();
	if ( $api_base === '' ) {
		return array();
	}

	$url = rtrim( $api_base, '/' ) . '/public/releases?limit=200';
	$response = wp_remote_get( $url, array(
		'timeout' => 15,
		'headers' => array( 'Accept' => 'application/json' ),
	) );

	if ( is_wp_error( $response ) ) {
		return array();
	}

	$code = wp_remote_retrieve_response_code( $response );
	if ( $code !== 200 ) {
		return array();
	}

	$body = wp_remote_retrieve_body( $response );
	$data = json_decode( $body, true );
	if ( ! is_array( $data ) ) {
		return array();
	}

	$list = array();
	foreach ( $data as $item ) {
		if ( ! is_array( $item ) || ! isset( $item['id'], $item['title'] ) ) {
			continue;
		}
		$names = isset( $item['artist_names'] ) && is_array( $item['artist_names'] )
			? array_map( 'sanitize_text_field', $item['artist_names'] )
			: array();
		$list[] = array(
			'id'           => (int) $item['id'],
			'title'        => sanitize_text_field( $item['title'] ),
			'artist_names' => $names,
			'created_at'   => isset( $item['created_at'] ) ? sanitize_text_field( $item['created_at'] ) : '',
		);
	}

	set_transient( ZALMANIM_ARTISTS_RELEASES_CACHE_KEY, $list, ZALMANIM_ARTISTS_CACHE_TTL );
	return $list;
}

/**
 * Shortcode [zalmanim_artists]: output list of artists with Linktree links.
 *
 * Optional attributes:
 * - list_style: 'ul' (default) or 'ol' or 'comma'
 * - class: extra CSS class for the wrapper
 *
 * @param array $atts Shortcode attributes.
 * @return string HTML output.
 */
function zalmanim_artists_shortcode( $atts ) {
	$atts = shortcode_atts( array(
		'list_style' => 'ul',
		'class'      => '',
	), $atts, 'zalmanim_artists' );

	$artists = zalmanim_artists_fetch();
	if ( empty( $artists ) ) {
		return '<p class="zalmanim-artists-empty">' . esc_html__( 'No artists to display.', 'zalmanim-artists' ) . '</p>';
	}

	$linktree_base = zalmanim_artists_get_linktree_base();
	$css_class     = 'zalmanim-artists-list';
	if ( $atts['class'] !== '' ) {
		$css_class .= ' ' . sanitize_html_class( $atts['class'] );
	}

	$items = array();
	foreach ( $artists as $a ) {
		$name = esc_html( $a['name'] );
		$url  = null;
		if ( ! empty( $a['linktree_url'] ) ) {
			$url = $a['linktree_url'];
		} elseif ( $linktree_base !== '' ) {
			$url = rtrim( $linktree_base, '/' ) . '/' . $a['artist_id'];
		}
		if ( $url !== null ) {
			$items[] = '<a href="' . esc_url( $url ) . '" rel="noopener noreferrer" target="_blank">' . $name . '</a>';
		} else {
			$items[] = '<span>' . $name . '</span>';
		}
	}

	$html = '';
	if ( $atts['list_style'] === 'ol' ) {
		$html = '<ol class="' . esc_attr( $css_class ) . '"><li>' . implode( '</li><li>', $items ) . '</li></ol>';
	} elseif ( $atts['list_style'] === 'comma' ) {
		$html = '<p class="' . esc_attr( $css_class ) . '">' . implode( ', ', $items ) . '</p>';
	} else {
		$html = '<ul class="' . esc_attr( $css_class ) . '"><li>' . implode( '</li><li>', $items ) . '</li></ul>';
	}

	return $html;
}

/**
 * Shortcode [zalmanim_releases]: output list of label releases.
 *
 * Optional attributes:
 * - list_style: 'ul' (default) or 'ol' or 'comma'
 * - class: extra CSS class for the wrapper
 * - show_artists: '1' (default) to append artist names, '0' to show title only
 *
 * @param array $atts Shortcode attributes.
 * @return string HTML output.
 */
function zalmanim_releases_shortcode( $atts ) {
	$atts = shortcode_atts( array(
		'list_style'   => 'ul',
		'class'        => '',
		'show_artists' => '1',
	), $atts, 'zalmanim_releases' );

	$releases = zalmanim_releases_fetch();
	if ( empty( $releases ) ) {
		return '<p class="zalmanim-releases-empty">' . esc_html__( 'No releases to display.', 'zalmanim-artists' ) . '</p>';
	}

	$show_artists = $atts['show_artists'] !== '0' && $atts['show_artists'] !== 'false';
	$css_class    = 'zalmanim-releases-list';
	if ( $atts['class'] !== '' ) {
		$css_class .= ' ' . sanitize_html_class( $atts['class'] );
	}

	$items = array();
	foreach ( $releases as $r ) {
		$title = esc_html( $r['title'] );
		if ( $show_artists && ! empty( $r['artist_names'] ) ) {
			$title .= ' <span class="zalmanim-release-artists"> – ' . esc_html( implode( ', ', $r['artist_names'] ) ) . '</span>';
		}
		$items[] = $title;
	}

	$html = '';
	if ( $atts['list_style'] === 'ol' ) {
		$html = '<ol class="' . esc_attr( $css_class ) . '"><li>' . implode( '</li><li>', $items ) . '</li></ol>';
	} elseif ( $atts['list_style'] === 'comma' ) {
		$html = '<p class="' . esc_attr( $css_class ) . '">' . implode( ', ', $items ) . '</p>';
	} else {
		$html = '<ul class="' . esc_attr( $css_class ) . '"><li>' . implode( '</li><li>', $items ) . '</li></ul>';
	}

	return $html;
}

/**
 * Shortcode [zalmanim_demo_form]: display demo submission form (iframe to portal or embedded form).
 *
 * Optional attributes:
 * - mode: 'iframe' (default if portal URL is set) or 'form' (embedded form that submits to API)
 * - class: extra CSS class for the wrapper
 * - height: iframe height in px (default 600). Only for iframe mode.
 *
 * @param array $atts Shortcode attributes.
 * @return string HTML output.
 */
function zalmanim_demo_form_shortcode( $atts ) {
	$atts = shortcode_atts( array(
		'mode'   => '',
		'class'  => '',
		'height' => '600',
	), $atts, 'zalmanim_demo_form' );

	$portal_url = zalmanim_artists_get_portal_url();
	$api_base   = zalmanim_artists_get_api_base();
	$demo_token = zalmanim_artists_get_demo_token();

	$use_iframe = ( $atts['mode'] === 'iframe' ) || ( $atts['mode'] === '' && $portal_url !== '' );
	$use_form   = ( $atts['mode'] === 'form' ) || ( $atts['mode'] === '' && $portal_url === '' && $api_base !== '' );

	$css_class = 'zalmanim-demo-form';
	if ( $atts['class'] !== '' ) {
		$css_class .= ' ' . sanitize_html_class( $atts['class'] );
	}

	if ( $use_iframe && $portal_url !== '' ) {
		$height = absint( $atts['height'] );
		if ( $height < 200 ) {
			$height = 600;
		}
		$src = esc_url( rtrim( $portal_url, '/' ) );
		return '<div class="' . esc_attr( $css_class ) . '"><iframe title="' . esc_attr__( 'Demo submission form', 'zalmanim-artists' ) . '" src="' . $src . '" width="100%" height="' . $height . '" style="border:0;"></iframe></div>';
	}

	if ( $use_form && $api_base !== '' ) {
		return zalmanim_demo_form_render_embedded( $css_class );
	}

	return '<p class="zalmanim-demo-form-empty">' . esc_html__( 'Configure API base URL and optionally Portal URL or Demo token in Settings → Zalmanim Artists to display the demo form.', 'zalmanim-artists' ) . '</p>';
}

/**
 * Render embedded demo form (submits to API via WordPress backend).
 *
 * @param string $wrapper_class CSS class for wrapper.
 * @return string HTML output.
 */
function zalmanim_demo_form_render_embedded( $wrapper_class ) {
	$nonce = wp_nonce_field( 'zalmanim_demo_submit', 'zalmanim_demo_nonce', true, false );

	$msg = '';
	if ( isset( $_GET['zalmanim_demo_status'] ) ) {
		if ( $_GET['zalmanim_demo_status'] === 'success' ) {
			$msg = '<p class="zalmanim-demo-message zalmanim-demo-success">' . esc_html__( 'Thank you! Your demo was submitted successfully. Check your email for confirmation.', 'zalmanim-artists' ) . '</p>';
		} elseif ( $_GET['zalmanim_demo_status'] === 'error' && ! empty( $_GET['zalmanim_demo_error'] ) ) {
			$err = sanitize_text_field( wp_unslash( $_GET['zalmanim_demo_error'] ) );
			$msg = '<p class="zalmanim-demo-message zalmanim-demo-error">' . esc_html__( 'Submission failed:', 'zalmanim-artists' ) . ' ' . esc_html( $err ) . '</p>';
		}
	}

	ob_start();
	?>
	<div class="<?php echo esc_attr( $wrapper_class ); ?>">
		<?php echo $msg; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped -- message is escaped above ?>
		<form method="post" action="">
			<?php echo $nonce; // phpcs:ignore WordPress.Security.EscapeOutput.OutputNotEscaped ?>
			<p>
				<label for="zalmanim_demo_artist_name"><?php esc_html_e( 'Artist name', 'zalmanim-artists' ); ?> <span class="required">*</span></label><br/>
				<input type="text" id="zalmanim_demo_artist_name" name="zalmanim_demo_artist_name" required="required" value="" />
			</p>
			<p>
				<label for="zalmanim_demo_email"><?php esc_html_e( 'Email', 'zalmanim-artists' ); ?> <span class="required">*</span></label><br/>
				<input type="email" id="zalmanim_demo_email" name="zalmanim_demo_email" required="required" value="" />
			</p>
			<p>
				<label for="zalmanim_demo_links"><?php esc_html_e( 'Track link(s)', 'zalmanim-artists' ); ?> (<?php esc_html_e( 'e.g. SoundCloud, Spotify', 'zalmanim-artists' ); ?>)</label><br/>
				<textarea id="zalmanim_demo_links" name="zalmanim_demo_links" rows="2" placeholder="https://..."></textarea>
				<span class="description"><?php esc_html_e( 'One URL per line.', 'zalmanim-artists' ); ?></span>
			</p>
			<p>
				<label for="zalmanim_demo_message"><?php esc_html_e( 'Message', 'zalmanim-artists' ); ?></label><br/>
				<textarea id="zalmanim_demo_message" name="zalmanim_demo_message" rows="3"></textarea>
			</p>
			<p>
				<label><input type="checkbox" name="zalmanim_demo_consent" value="1" required="required" /> <?php esc_html_e( 'I agree to join the label mailing list and receive marketing and operational emails related to my demo.', 'zalmanim-artists' ); ?></label>
			</p>
			<p>
				<button type="submit" name="zalmanim_demo_submit" value="1"><?php esc_html_e( 'Send demo', 'zalmanim-artists' ); ?></button>
			</p>
		</form>
		<p class="description"><?php esc_html_e( 'To upload an MP3 file, use the full demo form on the artist portal.', 'zalmanim-artists' ); ?></p>
	</div>
	<?php
	return ob_get_clean();
}

/**
 * Handle demo form submission (POST to API with token).
 */
function zalmanim_handle_demo_submit() {
	if ( ! isset( $_POST['zalmanim_demo_submit'], $_POST['zalmanim_demo_nonce'] ) ) {
		return;
	}
	if ( ! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST['zalmanim_demo_nonce'] ) ), 'zalmanim_demo_submit' ) ) {
		return;
	}

	$redirect_base = wp_get_referer() ?: home_url( wp_unslash( isset( $_SERVER['REQUEST_URI'] ) ? $_SERVER['REQUEST_URI'] : '' ) );
	$redirect_base = remove_query_arg( array( 'zalmanim_demo_status', 'zalmanim_demo_error' ), $redirect_base );

	$api_base = zalmanim_artists_get_api_base();
	if ( $api_base === '' ) {
		wp_safe_redirect( add_query_arg( array( 'zalmanim_demo_status' => 'error', 'zalmanim_demo_error' => rawurlencode( __( 'API not configured.', 'zalmanim-artists' ) ) ), $redirect_base ) );
		exit;
	}

	$artist_name = isset( $_POST['zalmanim_demo_artist_name'] ) ? sanitize_text_field( wp_unslash( $_POST['zalmanim_demo_artist_name'] ) ) : '';
	$email       = isset( $_POST['zalmanim_demo_email'] ) ? sanitize_email( wp_unslash( $_POST['zalmanim_demo_email'] ) ) : '';
	$links_raw   = isset( $_POST['zalmanim_demo_links'] ) ? sanitize_textarea_field( wp_unslash( $_POST['zalmanim_demo_links'] ) ) : '';
	$message     = isset( $_POST['zalmanim_demo_message'] ) ? sanitize_textarea_field( wp_unslash( $_POST['zalmanim_demo_message'] ) ) : '';
	$consent     = ! empty( $_POST['zalmanim_demo_consent'] );

	if ( $artist_name === '' || $email === '' ) {
		wp_safe_redirect( add_query_arg( array( 'zalmanim_demo_status' => 'error', 'zalmanim_demo_error' => rawurlencode( __( 'Artist name and email are required.', 'zalmanim-artists' ) ) ), $redirect_base ) );
		exit;
	}

	$links = array_filter( array_map( 'trim', explode( "\n", str_replace( "\r", "\n", $links_raw ) ) ) );
	$links = array_values( array_filter( array_map( 'esc_url_raw', $links ) ) );

	$body = wp_json_encode( array(
		'artist_name'       => $artist_name,
		'email'             => $email,
		'consent_to_emails' => $consent,
		'message'           => $message !== '' ? $message : null,
		'links'             => $links,
		'source'            => 'wordpress_demo_form',
		'source_site_url'   => home_url( add_query_arg( array(), null ) ),
	) );

	$headers = array(
		'Content-Type' => 'application/json',
		'Accept'       => 'application/json',
	);
	$token = zalmanim_artists_get_demo_token();
	if ( $token !== '' ) {
		$headers['x-demo-token'] = $token;
	}

	$response = wp_remote_post( rtrim( $api_base, '/' ) . '/public/demo-submissions', array(
		'timeout' => 20,
		'headers' => $headers,
		'body'    => $body,
	) );

	if ( is_wp_error( $response ) ) {
		$err = $response->get_error_message();
		$redirect_base = wp_get_referer() ?: home_url( wp_unslash( isset( $_SERVER['REQUEST_URI'] ) ? $_SERVER['REQUEST_URI'] : '' ) );
		$redirect_base = remove_query_arg( array( 'zalmanim_demo_status', 'zalmanim_demo_error' ), $redirect_base );
		wp_safe_redirect( add_query_arg( array( 'zalmanim_demo_status' => 'error', 'zalmanim_demo_error' => rawurlencode( $err ) ), $redirect_base ) );
		exit;
	}

	$code = wp_remote_retrieve_response_code( $response );
	$redirect_base = wp_get_referer() ?: home_url( wp_unslash( isset( $_SERVER['REQUEST_URI'] ) ? $_SERVER['REQUEST_URI'] : '' ) );
	$redirect_base = remove_query_arg( array( 'zalmanim_demo_status', 'zalmanim_demo_error' ), $redirect_base );

	if ( $code >= 200 && $code < 300 ) {
		wp_safe_redirect( add_query_arg( 'zalmanim_demo_status', 'success', $redirect_base ) );
		exit;
	}

	$res_body = wp_remote_retrieve_body( $response );
	$detail   = __( 'Server error.', 'zalmanim-artists' );
	if ( $res_body !== '' ) {
		$json = json_decode( $res_body, true );
		if ( is_array( $json ) && isset( $json['detail'] ) ) {
			$detail = is_string( $json['detail'] ) ? $json['detail'] : wp_json_encode( $json['detail'] );
		}
	}
	wp_safe_redirect( add_query_arg( array( 'zalmanim_demo_status' => 'error', 'zalmanim_demo_error' => rawurlencode( $detail ) ), $redirect_base ) );
	exit;
}
add_action( 'template_redirect', 'zalmanim_handle_demo_submit' );

/**
 * Register settings and shortcodes.
 */
function zalmanim_artists_init() {
	add_shortcode( 'zalmanim_artists', 'zalmanim_artists_shortcode' );
	add_shortcode( 'zalmanim_releases', 'zalmanim_releases_shortcode' );
	add_shortcode( 'zalmanim_demo_form', 'zalmanim_demo_form_shortcode' );
}
add_action( 'init', 'zalmanim_artists_init' );

/**
 * Add settings page under Settings menu.
 */
function zalmanim_artists_add_settings_page() {
	add_options_page(
		__( 'Zalmanim Artists', 'zalmanim-artists' ),
		__( 'Zalmanim Artists', 'zalmanim-artists' ),
		'manage_options',
		'zalmanim-artists',
		'zalmanim_artists_render_settings_page'
	);
}
add_action( 'admin_menu', 'zalmanim_artists_add_settings_page' );

/**
 * Register settings.
 */
function zalmanim_artists_register_settings() {
	register_setting( 'zalmanim_artists_settings', 'zalmanim_artists_api_base', array(
		'type'              => 'string',
		'sanitize_callback' => function ( $v ) {
			$v = trim( (string) $v );
			return $v === '' ? '' : esc_url_raw( rtrim( $v, '/' ) );
		},
	) );
	register_setting( 'zalmanim_artists_settings', 'zalmanim_artists_linktree_base', array(
		'type'              => 'string',
		'sanitize_callback' => function ( $v ) {
			$v = trim( (string) $v );
			return $v === '' ? '' : esc_url_raw( rtrim( $v, '/' ) );
		},
	) );
	register_setting( 'zalmanim_artists_settings', 'zalmanim_artists_portal_url', array(
		'type'              => 'string',
		'sanitize_callback' => function ( $v ) {
			$v = trim( (string) $v );
			return $v === '' ? '' : esc_url_raw( rtrim( $v, '/' ) );
		},
	) );
	register_setting( 'zalmanim_artists_settings', 'zalmanim_artists_demo_token', array(
		'type'              => 'string',
		'sanitize_callback' => 'sanitize_text_field',
	) );
}
add_action( 'admin_init', 'zalmanim_artists_register_settings' );

/**
 * Render settings page HTML.
 */
function zalmanim_artists_render_settings_page() {
	if ( ! current_user_can( 'manage_options' ) ) {
		return;
	}

	// Clear cache when user clicked "Clear cache"
	if ( isset( $_POST['zalmanim_artists_clear_cache'] ) && check_admin_referer( 'zalmanim_artists_clear_cache' ) ) {
		delete_transient( ZALMANIM_ARTISTS_CACHE_KEY );
		delete_transient( ZALMANIM_ARTISTS_RELEASES_CACHE_KEY );
		echo '<div class="notice notice-success"><p>' . esc_html__( 'Cache cleared.', 'zalmanim-artists' ) . '</p></div>';
	}

	$api_base      = zalmanim_artists_get_api_base();
	$linktree_base = zalmanim_artists_get_linktree_base();
	$portal_url    = zalmanim_artists_get_portal_url();
	$demo_token    = zalmanim_artists_get_demo_token();
	?>
	<div class="wrap">
		<h1><?php echo esc_html( get_admin_page_title() ); ?></h1>
		<form action="options.php" method="post">
			<?php settings_fields( 'zalmanim_artists_settings' ); ?>
			<table class="form-table" role="presentation">
				<tr>
					<th scope="row">
						<label for="zalmanim_artists_api_base"><?php esc_html_e( 'API base URL', 'zalmanim-artists' ); ?></label>
					</th>
					<td>
						<input type="url" id="zalmanim_artists_api_base" name="zalmanim_artists_api_base"
							   value="<?php echo esc_attr( $api_base ); ?>"
							   class="regular-text" placeholder="https://api.example.com"/>
						<p class="description"><?php esc_html_e( 'Base URL of the Zalmanim API (no trailing slash). Example: https://api.zalmanim.com', 'zalmanim-artists' ); ?></p>
					</td>
				</tr>
				<tr>
					<th scope="row">
						<label for="zalmanim_artists_linktree_base"><?php esc_html_e( 'Public Linktree base URL (optional)', 'zalmanim-artists' ); ?></label>
					</th>
					<td>
						<input type="url" id="zalmanim_artists_linktree_base" name="zalmanim_artists_linktree_base"
							   value="<?php echo esc_attr( $linktree_base ); ?>"
							   class="regular-text" placeholder="https://artists.example.com/linktree"/>
						<p class="description"><?php esc_html_e( 'When an artist has no Linktree URL, link to this base + artist ID. Leave empty to show name only.', 'zalmanim-artists' ); ?></p>
					</td>
				</tr>
				<tr>
					<th scope="row">
						<label for="zalmanim_artists_portal_url"><?php esc_html_e( 'Artist portal URL (optional)', 'zalmanim-artists' ); ?></label>
					</th>
					<td>
						<input type="url" id="zalmanim_artists_portal_url" name="zalmanim_artists_portal_url"
							   value="<?php echo esc_attr( $portal_url ); ?>"
							   class="regular-text" placeholder="https://artists.example.com"/>
						<p class="description"><?php esc_html_e( 'Used to embed the full demo form (with file upload) in an iframe. Example: https://artists.zalmanim.com', 'zalmanim-artists' ); ?></p>
					</td>
				</tr>
				<tr>
					<th scope="row">
						<label for="zalmanim_artists_demo_token"><?php esc_html_e( 'Demo submission token (optional)', 'zalmanim-artists' ); ?></label>
					</th>
					<td>
						<input type="text" id="zalmanim_artists_demo_token" name="zalmanim_artists_demo_token"
							   value="<?php echo esc_attr( $demo_token ); ?>"
							   class="regular-text" autocomplete="off"/>
						<p class="description"><?php esc_html_e( 'If the API requires a token for demo submissions, set it here. It is sent as x-demo-token header.', 'zalmanim-artists' ); ?></p>
					</td>
				</tr>
			</table>
			<?php submit_button(); ?>
		</form>
		<hr/>
		<h2><?php esc_html_e( 'Shortcodes', 'zalmanim-artists' ); ?></h2>
		<p><strong>[zalmanim_artists]</strong> — <?php esc_html_e( 'List of artists who have released tracks, with Linktree links.', 'zalmanim-artists' ); ?></p>
		<ul style="list-style: disc; margin-left: 2em;">
			<li><code>list_style</code>: <code>ul</code>, <code>ol</code>, <code>comma</code></li>
			<li><code>class</code>: extra CSS class</li>
		</ul>
		<p><strong>[zalmanim_releases]</strong> — <?php esc_html_e( 'List of label releases (title and artist names).', 'zalmanim-artists' ); ?></p>
		<ul style="list-style: disc; margin-left: 2em;">
			<li><code>list_style</code>: <code>ul</code>, <code>ol</code>, <code>comma</code></li>
			<li><code>show_artists</code>: <code>1</code> (default) or <code>0</code></li>
			<li><code>class</code>: extra CSS class</li>
		</ul>
		<p><strong>[zalmanim_demo_form]</strong> — <?php esc_html_e( 'Demo submission form. If Portal URL is set, embeds the portal in an iframe (full form with file upload). Otherwise shows an embedded form that submits to the API (links + message only; no file upload).', 'zalmanim-artists' ); ?></p>
		<ul style="list-style: disc; margin-left: 2em;">
			<li><code>mode</code>: <code>iframe</code> or <code>form</code> to force one mode</li>
			<li><code>height</code>: iframe height in px (default 600)</li>
			<li><code>class</code>: extra CSS class</li>
		</ul>
		<p><?php esc_html_e( 'Examples:', 'zalmanim-artists' ); ?></p>
		<ul style="list-style: disc; margin-left: 2em;">
			<li><code>[zalmanim_artists]</code> <code>[zalmanim_releases]</code> <code>[zalmanim_demo_form]</code></li>
		</ul>
		<hr/>
		<form method="post">
			<?php wp_nonce_field( 'zalmanim_artists_clear_cache' ); ?>
			<p>
				<button type="submit" name="zalmanim_artists_clear_cache" class="button"><?php esc_html_e( 'Clear cache', 'zalmanim-artists' ); ?></button>
				<span class="description"><?php esc_html_e( 'Artists and releases data is cached for 15 minutes.', 'zalmanim-artists' ); ?></span>
			</p>
		</form>
	</div>
	<?php
}
