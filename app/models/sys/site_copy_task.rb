class Sys::SiteCopyTask
  include SS::Model::Task
  include Sys::Permission

  set_permission_name "sys_sites", :edit

  default_scope ->{ where(name: "sys::site_copy") }

  # field :results, type: Hash
  field :target_host_name, type: String
  field :target_host_host, type: String
  field :target_host_domains, type: SS::Extensions::Words
  belongs_to :source_site, class_name: "SS::Site"
  field :copy_contents, type: SS::Extensions::Words

  permit_params :target_host_name, :target_host_host, :target_host_domains
  permit_params :source_site_id
  permit_params copy_contents: []

  validates :target_host_name, presence: true, length: { maximum: 40 }
  validates :target_host_host, presence: true, length: { minimum: 3, maximum: 16 }
  validate :validate_target_host_host, if: ->{ target_host_host.present? }
  validates :target_host_domains, presence: true
  validate :validate_target_host_domains, if: ->{ target_host_domains.present? }
  validates :source_site_id, presence: true

  def clear_params
    self.target_host_name = nil
    self.target_host_host = nil
    self.target_host_domains = nil
    self.source_site_id = nil
    self.copy_contents = nil
  end

  private

  def validate_target_host_host
    return if target_host_host.blank?
    errors.add :target_host_host, :duplicate if SS::Site.ne(id: id).where(host: target_host_host).exists?
  end

  def validate_target_host_domains
    return if target_host_domains.blank?
    errors.add :target_host_domains, :duplicate if SS::Site.ne(id: id).any_in(domains: target_host_domains).exists?
  end
end
