require "test_helper"

class ThemeTest < ActionDispatch::IntegrationTest
  test "theme selector is accessible and its local bootstrap precedes the stylesheet" do
    get root_path
    assert_select 'select[data-theme-picker][aria-label="Tema da interface"]', 1
    assert_select 'select[data-theme-picker] option[value="light"]', text: /Claro/
    assert_select 'select[data-theme-picker] option[value="dark"]', text: /Escuro/
    page = Nokogiri::HTML(response.body)
    bootstrap = page.at_css('head script[src*="theme_boot"]')
    assert bootstrap
    assert_operator response.body.index(bootstrap.to_html.split(">").first), :<, response.body.index('rel="stylesheet"')
    get bootstrap["src"]
    assert_response :success
    assert_match "chromehoot-theme", response.body
  end
end
