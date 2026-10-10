require_relative '../config/application'
require_relative 'utils/pid_manager'
require_relative 'processors/ad_list_processor'
require_relative 'processors/exclusions_loader'
require_relative 'services/list_manager'
require_relative 'services/policy_manager'

# Initialize PID Manager and check for existing processes
pid_manager = Utils::PidManager.new
pid_manager.check_and_write_pid

# Main script
Utils::Log.logger.info('Starting script...')

# Load exclusions
exclusions = Processors::ExclusionsLoader.load_exclusions(EXCLUSIONS_FILE)


ad_list_content =
  Processors::AdListProcessor.download_ad_list(AD_LIST_URL)

# Download and merge the personal ad list, if configured
personal_ad_list_url = ENV["PERSONAL_AD_LIST_URL"]

if personal_ad_list_url && !personal_ad_list_url.empty?
  puts "Downloading personal ad list..."

  personal_ad_list_content =
    Processors::AdListProcessor.download_ad_list(personal_ad_list_url)

  ad_list_content = [
    ad_list_content,
    personal_ad_list_content
  ].join("\n")
end

# Process the combined list using the existing validator
hostnames =
  Processors::AdListProcessor.process_ad_list(
    ad_list_content,
    exclusions
  )

domain_chunks = hostnames.each_slice(CLOUDFLARE_LIST_ITEM_LIMIT).to_a
Utils::Log.logger.info("Splitting ad hostnames into #{domain_chunks.size} lists...")

existing_lists = Services::ListManager.fetch_existing_lists
existing_policies = Services::PolicyManager.fetch_existing_policies

# Find and remove our previous policy, if present.
existing_policy = existing_policies.find { |policy| policy['name'] == AD_LIST_NAME }
Services::PolicyManager.delete_policy(existing_policy['id']) if existing_policy

# Find an unused precedence, ignoring our old policy.
used_precedences = existing_policies
  .reject { |policy| policy['name'] == AD_LIST_NAME }
  .filter_map { |policy| policy['precedence']&.to_i }

precedence = (1..10000).find do |value|
  !used_precedences.include?(value)
end

raise 'No available Cloudflare policy precedence found' unless precedence

# Process each domain chunk and manage lists
list_ids = []
domain_chunks.each_with_index do |chunk, index|
  Utils::Log.logger.info("Processing list #{index + 1} of #{domain_chunks.size}...")
  list_name = "#{AD_LIST_NAME} Part #{index + 1}"
  list_description = "Part #{index + 1} of #{AD_LIST_NAME}"
  existing_list = existing_lists.find { |list| list['name'] == list_name }
  Services::ListManager.delete_list(existing_list['id']) if existing_list

  list = Services::ListManager.create_list(list_name, list_description, chunk)
  list_ids << { 'id' => list['id'] } if list
end

# Create new policy
Services::PolicyManager.create_policy(
  AD_LIST_NAME,
  'Policy blocking ad domains',
  list_ids,
  precedence
)Utils::Log.logger.info('Script completed.')
