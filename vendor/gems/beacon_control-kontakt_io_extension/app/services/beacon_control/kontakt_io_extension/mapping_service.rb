module BeaconControl
  module KontaktIoExtension
    class MappingService
      # @param [Admin] current_admin
      def initialize(current_admin)
        @admin = current_admin
      end

      # @param [Hash<String, Array<String>>] params
      def sync!(params)
        ActiveRecord::Base.transaction do
          sync_venues!(params)
          sync_beacons!(params)
        end
      end

      # @param [Hash<String, Array<String>>] params
      def sync_venues!(params)
        fetch_options!(params)
        venues.each do |data|
          zone = get_zone(data)
          if zone.kontakt_io_mapping.blank?
            zone.build_kontakt_io_mapping(kontakt_uid: data.id)
          end
          if !data.db? || update?
            zone.account = admin.account
            zone.save!
          end
        end
      end

      # @param [Hash<String, Array<String>>] params
      def sync_beacons!(params)
        fetch_options!(params)
        beacons.each do |data|
          beacon = get_beacon(data)
          if beacon.kontakt_io_mapping.blank?
            beacon.build_kontakt_io_mapping(kontakt_uid: data.unique_id)
          end
          if !data.db? || update?
            beacon.save!
            assign_to_zone!(data, beacon)
          end
        end
      end

      # private
      attr_reader :admin, :selected_beacons, :selected_venues

      # @param [::KontaktIo::Resource::Zone] data
      # @return [::Zone]
      def get_zone(data)
        find_zone(data) || build_zone(data)
      end

      # @param [::KontaktIo::Resource::Zone] data
      # @return [::Zone]
      def find_zone(data)
        ::Zone.kontakt_io.merge(KontaktIoMapping.with_uid(data.id)).first
      end

      # @param [::KontaktIo::Resource::Zone] data
      # @return [::Zone]
      def build_zone(data)
        ::Zone.new(name: data.name)
      end

      # @param [KontaktIo::Resource::Beacon] kontakt_beacon
      # @return [::Beacon]
      def get_beacon(kontakt_beacon)
        find_beacon(kontakt_beacon) || build_beacon(kontakt_beacon)
      end

      # @param [KontaktIo::Resource::Beacon] kontakt_beacon
      # @return [::Beacon]
      def find_beacon(kontakt_beacon)
        ::Beacon.kontakt_io.merge(KontaktIoMapping.with_uid(kontakt_beacon.unique_id)).first
      end

      # @param [KontaktIo::Resource::Beacon] kontakt_beacon
      # @return [::Beacon]
      def build_beacon(kontakt_beacon)
        ::Beacon::Factory.new(
          admin,
          name:  "[#{kontakt_beacon.unique_id}] #{kontakt_beacon.name}",
          uuid:  kontakt_beacon.proximity,
          major: kontakt_beacon.major,
          minor: kontakt_beacon.minor,
          vendor: 'Kontakt'
        ).build
      end

      # @return [Array<KontaktIo::Resource::Beacon>]
      def beacons
        @beacons ||= api.beacons.select do |beacon|
          beacon.was_imported = beacon_imported?(beacon.unique_id)
          return true if selected_beacons.nil?
          selected_beacons.include?(beacon.unique_id)
        end
      end

      # @return [Array<KontaktIo::Resource::Venue>]
      def venues
        @venues ||= load_venues
      end

      def load_venues
        if selected_beacons.any?
          beacons.map do |beacon|
            beacon.venue
          end.compact.uniq(&:id).each do |venue|
            venue.was_imported = zone_mapped_uids.include?(venue.id)
          end
        else
          api.venues.select do |venue|
            venue.was_imported = zone_mapped_uids.include?(venue.id)
            selected_venues.nil? ? selected_venues.include?(venue.id) : true
          end
        end
      end

      # @return [Array<String>]
      def zone_mapped_uids
        @zone_mapped_uids ||= KontaktIoMapping.zones.pluck(:kontakt_uid)
      end

      # @return [Array<String>]
      def beacon_mapped_uids
        @beacon_mapped_uids ||= KontaktIoMapping.beacons.pluck(:kontakt_uid)
      end

      # @return [KontaktIo::ApiClient]
      def api
        @api ||= KontaktIo::ApiClient.new(KontaktIo::ApiClient.account_api_key(admin.account))
      end

      def fetch_options!(params)
        @selected_beacons = params.fetch(:beacons, []) unless @selected_beacons
        @selected_venues  = params.fetch(:venues, []) unless @selected_venues
        @update = params[:update] == true
      end

      # @return [TrueClass|FalseClass]
      def update?
        @update
      end

      # @param [String] uid
      # @return [TrueClass|FalseClass]
      def beacon_imported?(uid)
        beacon_mapped_uids.include?(uid)
      end

      # @param [String] uid
      # @return [TrueClass|FalseClass]
      def zone_imported?(uid)
        zone_mapped_uids.include?(uid)
      end

      def assign_to_zone!(data, beacon)
        return unless data.venue.present?
        return unless data.venue.id.present?
        zone = Zone.with_kontakt_uid(data.venue.id).first
        zone.beacons << beacon if zone
      end
    end
  end
end