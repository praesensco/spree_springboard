module SpreeSpringboard
  module Resource
    module Import
      class ReturnAuthorization < SpreeSpringboard::Resource::Import::Base
        include SpreeSpringboard::Resource::Clients::ReturnAuthorizationClient
        self.spree_class = Spree::ReturnAuthorization

        #
        # Import Springboard items from last day
        #
        def import_last_day!
          import_all_perform(client_query_last_day)
        end

        def import_last_three_days!
          import_all_perform(client_query_last_three_days)
        end

        #
        # Create ReturnAuthorization from Springboard Return Ticket
        #
        def create_from_springboard_resource(springboard_return)
          # Find invoice entry in Spree::SpringboardResource related to springboard_return
          invoice_resource = find_spree_invoice(springboard_return)

          # Quietly return if no invoice entry is found
          # May be an order handled outside of Spree
          return false if invoice_resource.blank?

          # Load order related to the Invoice entry
          order = invoice_resource.parent

          # Create ReturnAuthorization matching springboard_return
          return_authorization = create_spree_return_authorization(order, springboard_return)

          # Prepare Spree ReturnItems and select matching springboard_return_lines
          return_authorization_items = select_spree_return_items(springboard_return, return_authorization)

          # Raise exception if springboard_return_lines do not match available ReturnItems
          raise "Invoice #{springboard_return[:id]}::NoValidReturnItems" if return_authorization_items.blank?

          # Add ReturnItems to ReturnAuthorization
          return_authorization.return_items = return_authorization_items

          # Create CustomerReturn for ReturnAuthorization
          create_spree_customer_return(return_authorization)

          true
        end

        #
        # Find invoice entry in Spree::SpringboardResource related to springboard_return
        #
        def find_spree_invoice(springboard_return)
          Spree::SpringboardResource.find_by(
            resource_type: 'invoice',
            springboard_id: springboard_return[:parent_transaction_id]
          )
        end

        #
        # Prepare Spree Return Items and select to match springboard_return_lines
        #
        def select_spree_return_items(springboard_return, return_authorization)
          returned_springboard_items = springboard_return_items(springboard_return)
          available_spree_return_items = spree_return_items(return_authorization)
          selected_spree_return_items = []

          returned_springboard_items.each do |springboard_item|
            item_index = find_available_spree_return_item_index(available_spree_return_items, springboard_item)
            if item_index.nil?
              raise "Invoice #{springboard_return[:id]}::NoReturnItem::#{springboard_item[:item_id]}"
            end

            return_quantity = -springboard_item[:qty]
            unit_quantity = available_spree_return_items[item_index].inventory_unit.quantity
            if unit_quantity > return_quantity
              split_inventory_unit = available_spree_return_items[item_index].
                                     inventory_unit.
                                     split_inventory!(return_quantity)
              available_spree_return_items[item_index].inventory_unit = split_inventory_unit
              available_spree_return_items[item_index].pre_tax_amount *= return_quantity / unit_quantity
            end
            selected_spree_return_items << available_spree_return_items[item_index]
            available_spree_return_items.delete_at(item_index)
          end
          selected_spree_return_items
        end

        #
        # Helper method - find available Spree ReturnItem in array
        #
        def find_available_spree_return_item_index(available_spree_return_items, springboard_item)
          available_spree_return_items.find_index do |spree_item|
            spree_item.variant.springboard_id == springboard_item[:item_id] &&
              spree_item.inventory_unit.quantity >= -springboard_item[:qty]
          end
        end

        #
        # Load Return Ticet Lines from Springboard
        #
        def springboard_return_items(springboard_return)
          lines = SpreeSpringboard.
                  client["sales/tickets/#{springboard_return[:id]}/lines"].query(per_page: :all).get.body.results
          used_lines = lines.reject { |line| line.type != 'ItemLine' || line.qty.zero? }
          used_lines.map do |line|
            { item_id: line[:item_id], qty: line[:qty] }
          end
        end

        #
        # Create CustomerReturn for ReturnAuthorization
        #
        def create_spree_customer_return(return_authorization)
          cr = Spree::CustomerReturn.new(
            stock_location: spree_stock_location
          )
          cr.return_items = return_authorization.return_items
          cr.save!
          cr
        end

        #
        # Create ReturnAuthorization
        #
        def create_spree_return_authorization(order, springboard_return)
          return_authorization = Spree::ReturnAuthorization.new(
            order: order,
            stock_location: spree_stock_location,
            return_authorization_reason_id: Spree::ReturnAuthorizationReason.active.first.id,
            memo: "Springboard Return ##{springboard_return[:id]}"
          )

          unless return_authorization.save
            raise "Unable to create return authorization for order #{ order.id }: #{ return_authorization.errors.full_messages.join(', ')}"
          end

          return_authorization.springboard_id = springboard_return[:id]
          return_authorization
        end

        #
        # Preapre ReturnItems for the created ReturnAuthorization
        #
        def spree_return_items(return_authorization)
          all_inventory_units = return_authorization.order.inventory_units
          associated_inventory_units = return_authorization.return_items.map(&:inventory_unit)
          unassociated_inventory_units = all_inventory_units - associated_inventory_units

          unassociated_inventory_units.map do |new_unit|
            Spree::ReturnItem.new(inventory_unit: new_unit).tap(&:set_default_pre_tax_amount)
          end
        end

        #
        # StockLocation for Springboard integration
        #
        def spree_stock_location
          Spree::StockLocation.find_by(default: true)
        end
      end
    end
  end
end
