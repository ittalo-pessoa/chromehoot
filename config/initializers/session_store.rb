Rails.application.config.session_store :cookie_store, key: "_chromehoot_session", httponly: true, same_site: :lax, expire_after: 12.hours
