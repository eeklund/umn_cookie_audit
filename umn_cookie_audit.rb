#!/usr/bin/env ruby
require "optparse"
require "csv"
require "uri"
require "json"
require "time"
require "ferrum"

$stdout.sync = true

def log(msg)
  puts "[#{Time.now.utc.iso8601}] #{msg}"
end

COOKIECUTTER_URL = "https://apps.lib.umn.edu/cookiecutter/".freeze
NO_COOKIES_TEXT = "No cookies were found that are eligible for deletion.".freeze

def browser_path
  if ENV["BROWSER_PATH"] && File.exist?(ENV["BROWSER_PATH"])
    ENV["BROWSER_PATH"]
  else
    "/usr/bin/chromium"
  end
end

def new_browser(headless:, timeout:)
  Ferrum::Browser.new(
    headless: headless,
    timeout: timeout,
    browser_path: browser_path,
    browser_options: { 'no-sandbox' => nil, 'disable-dev-shm-usage' => nil }
  )
end

def cookiecutter_verdict(browser)
  browser.goto(COOKIECUTTER_URL)
  body = browser.body
  ok = body.include?(NO_COOKIES_TEXT)
  verdict_text = ok ? NO_COOKIES_TEXT : body
  [ok, verdict_text]
end

def collect_cookies(browser)
  browser.cookies.all.values.map do |cookie|
    {
      "name" => cookie.name,
      "value" => cookie.value,
      "domain" => cookie.domain,
      "path" => cookie.path,
      "expires" => cookie.expires,
      "httpOnly" => cookie.httponly?,
      "secure" => cookie.secure?,
      "sameSite" => cookie.samesite,
      "session" => cookie.session?,
      "size" => cookie.size,
      "priority" => cookie.priority,
      "sourceScheme" => cookie.source_scheme,
      "sourcePort" => cookie.source_port
    }.compact
  end
end

def offending_cookies(cookies)
  cookies.select do |cookie|
    domain = cookie["domain"].to_s.downcase
    domain == "umn.edu" || domain == ".umn.edu"
  end
end

def remediation_for(offending_names, url)
  host = URI.parse(url).host
  if offending_names.empty?
    "No action needed"
  elsif offending_names.any? { |n| n.start_with?("_ga") || n == "_gid" || n.start_with?("_gat") }
    "Update GA/gtag cookie scope: set cookie_domain to #{host} in your GA4 Configuration tag (GTM) or gtag config, remove legacy UA tags or GA Settings that force cookieDomain=.umn.edu, publish, then verify with CookieCutter"
  else
    "Scope cookies to subdomain #{host}: audit GTM/gtag or app code to avoid setting cookies on .umn.edu, publish changes, then verify with CookieCutter"
  end
end

options = {
  input: "/data/sites.txt",
  output: "/data/report.csv",
  delay: 4,
  headless: true,
  timeout: 25,
  verify_cookiecutter: true
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby umn_cookie_audit.rb [options]"
  opts.on("--sites FILE", "Text file of sites (one URI per line)") { |v| options[:input] = v }
  opts.on("--output FILE", "CSV output file") { |v| options[:output] = v }
  opts.on("--delay SECONDS", Integer, "Seconds to wait after page load") { |v| options[:delay] = v }
  opts.on("--timeout SECONDS", Integer, "Navigation timeout") { |v| options[:timeout] = v }
  opts.on("--headful", "Run with a visible window") { options[:headless] = false }
  opts.on("--no-verify-cookiecutter", "Skip post-visit CookieCutter verdict check") { options[:verify_cookiecutter] = false }
end.parse!

sites = File.readlines(options[:input], chomp: true).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }

log "Starting UMN cookie audit for #{sites.size} site#{sites.size == 1 ? '' : 's'}..."

CSV.open(options[:output], "w") do |csv|
  csv << [
    "site",
    "offending?",
    "offending_cookie_count",
    "offending_cookie_names",
    "offending_cookie_sizes",
    "offending_total_size",
    "cookiecutter_ok",
    "cookiecutter_excerpt",
    "remediation",
    "all_cookies_json"
  ]

  sites.each_with_index do |raw, i|
    url = raw =~ %r{\Ahttps?://}i ? raw : "https://#{raw}"
    log "Starting: [#{i + 1}/#{sites.size}] #{url}"

    offending = []
    offending_names = []
    offending_sizes = ""
    offending_total_size = 0
    cookiecutter_ok = nil
    cookiecutter_excerpt = nil
    remediation = ""

    begin
      browser = new_browser(headless: options[:headless], timeout: options[:timeout])
      browser.cookies.clear

      browser.goto(url)
      sleep options[:delay]

      cookies = collect_cookies(browser)
      offending = offending_cookies(cookies)
      offending_names = offending.map { |c| c["name"] }.uniq.sort
      offending_sizes = offending.map { |c| "#{c["name"]}:#{c["size"]}" }.join("|")
      offending_total_size = offending.map { |c| c["size"].to_i }.sum
      remediation = remediation_for(offending_names, url)

      if options[:verify_cookiecutter]
        cookiecutter_ok, verdict_text = cookiecutter_verdict(browser)
        cookiecutter_excerpt = verdict_text[0, 4000]
      end

      csv << [
        url,
        offending.any? ? "yes" : "no",
        offending.size,
        offending_names.join("|"),
        offending_sizes,
        offending_total_size,
        cookiecutter_ok.nil? ? "" : (cookiecutter_ok ? "true" : "false"),
        cookiecutter_excerpt.to_s,
        remediation,
        cookies.to_json
      ]
    rescue => e
      csv << [
        url,
        "error",
        0,
        "",
        "",
        0,
        "",
        "",
        "",
        { error: e.class.to_s, message: e.message }.to_json
      ]
    ensure
      browser&.quit
    end
  end
end

log "Scan complete. Results written to #{options[:output]}"

