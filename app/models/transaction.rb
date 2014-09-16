# == Schema Information
#
# Table name: transactions
#
#  id                                :integer          not null, primary key
#  starter_id                        :string(255)      not null
#  listing_id                        :integer          not null
#  conversation_id                   :integer
#  automatic_confirmation_after_days :integer
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  community_id                      :integer          not null
#  starter_skipped_feedback          :boolean          default(FALSE)
#  author_skipped_feedback           :boolean          default(FALSE)
#

class Transaction < ActiveRecord::Base
  attr_accessible(
    :community_id,
    :starter_id,
    :listing_id,
    :automatic_confirmation_after_days,
    :author_skipped_feedback,
    :starter_skipped_feedback
  )
  attr_accessor :contract_agreed

  belongs_to :community
  belongs_to :listing
  has_many :transaction_transitions, dependent: :destroy, foreign_key: :transaction_id
  has_one :payment, foreign_key: :transaction_id
  has_one :booking, :dependent => :destroy
  belongs_to :starter, :class_name => "Person", :foreign_key => "starter_id"
  belongs_to :conversation
  has_many :testimonials

  # Delegate methods to state machine
  delegate :can_transition_to?, :transition_to!, :transition_to, :current_state,
           to: :state_machine

  delegate :author, to: :listing
  delegate :title, to: :listing, prefix: true

  accepts_nested_attributes_for :booking

  scope :for_person, -> (person){
    joins(:listing)
    .where("listings.author_id = ? OR starter_id = ?", person.id, person.id)
  }

  def state_machine
    @state_machine ||= TransactionProcess.new(self, transition_class: TransactionTransition)
  end

  def status=(new_status)
    transition_to! new_status.to_sym
  end

  def status
    current_state
  end

  def payment_attributes=(attributes)
    payment = initialize_payment

    if attributes[:sum]
      # Simple payment form
      initialize_braintree_payment!(payment, attributes[:sum], attributes[:currency])
    else
      # Complex (multi-row) payment form
      initialize_checkout_payment!(payment, attributes[:payment_rows])
    end

    payment.save!
  end

  # TODO Remove this
  def initialize_payment
    payment ||= community.payment_gateway.new_payment
    payment.payment_gateway ||= community.payment_gateway
    payment.conversation = self
    payment.status = "pending"
    payment.payer = starter
    payment.recipient = author
    payment.community = community
    payment
  end

  def initialize_braintree_payment!(payment, sum, currency)
    sum_in_cents = sum.to_f*100
    payment.sum = Money.new(sum_in_cents, currency)
  end

  def initialize_checkout_payment!(payment, rows)
    rows.each { |row| payment.rows.build(row.merge(:currency => "EUR")) unless row["title"].blank? }
  end

  def should_notify?(user)
    super(user) || (status == "pending" && author == user)
  end

  # If listing is an offer, return request, otherwise return offer
  def discussion_type
    listing.transaction_type.is_request? ? "offer" : "request"
  end

  def has_feedback_from?(person)
    if author == person
      testimonial_from_author.present?
    else
      testimonial_from_starter.present?
    end
  end

  def feedback_skipped_by?(person)
    if author == person
      author_skipped_feedback?
    else
      starter_skipped_feedback?
    end
  end

  def waiting_feedback_from?(person)
    if author == person
      testimonial_from_author.blank? && !author_skipped_feedback?
    else
      testimonial_from_starter.blank? && !starter_skipped_feedback?
    end
  end

  def has_feedback_from_both_participants?
    testimonial_from_author.present? && testimonial_from_starter.present?
  end

  def testimonial_from_author
    testimonials.find { |testimonial| testimonial.author_id == author.id }
  end

  def testimonial_from_starter
    testimonials.find { |testimonial| testimonial.author_id == starter.id }
  end

  def offerer
    participations.find { |p| listing.offerer?(p) }
  end

  def requester
    participations.find { |p| listing.requester?(p) }
  end

  def participations
    [author, starter]
  end

  def payer
    starter
  end

  def payment_receiver
    author
  end

  # If payment through Sharetribe is required to
  # complete the transaction, return true, whether the payment
  # has been conducted yet or not.
  def requires_payment?(community)
    listing.payment_required_at?(community)
  end

  # Return true if the next required action is the payment
  def waiting_payment?(community)
    requires_payment?(community) && status.eql?("accepted")
  end

  # Return true if the transaction is in a state that it can be confirmed
  def can_be_confirmed?
    can_transition_to?(:confirmed)
  end

  # Return true if the transaction is in a state that it can be canceled
  def can_be_canceled?
    can_transition_to?(:canceled)
  end

  def with_type(&block)
    block.call(:listing_conversation)
  end

  def latest_activity
    (transaction_transitions + conversation.messages).max
  end

  def preauthorization_expire_at
    preauthorization_expires = payment.preauthorization_expiration_days.days.from_now.to_date

    if booking.present?
      booking.end_on < preauthorization_expires ? booking.end_on : preauthorization_expires
    else
      preauthorization_expires
    end
  end

  # Give person (starter or listing author) and get back the other
  #
  # Note: I'm not sure whether we want to have this method or not but at least it makes refactoring easier.
  def other_party(person)
    person == starter ? listing.author : starter
  end
end
