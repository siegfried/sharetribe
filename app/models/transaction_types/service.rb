# == Schema Information
#
# Table name: transaction_types
#
#  id                         :integer          not null, primary key
#  type                       :string(255)
#  community_id               :integer
#  sort_priority              :integer
#  price_field                :boolean
#  preauthorize_payment       :boolean          default(FALSE)
#  price_quantity_placeholder :string(255)
#  price_per                  :string(255)
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  url                        :string(255)
#
# Indexes
#
#  index_transaction_types_on_community_id  (community_id)
#  index_transaction_types_on_url           (url)
#

class Service < Offer

  DEFAULTS = {
    price_field: 1,
    price_quantity_placeholder: nil,
    price_per: "day"
  }

  before_validation(:on => :create) do
    self.price_field ||= DEFAULTS[:price_field]
    self.price_quantity_placeholder ||= DEFAULTS[:price_quantity_placeholder]
  end

end
