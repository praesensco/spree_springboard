module SpreeSpringboard
  class ImportReturnsJob < ApplicationJob
    queue_as :springboard

    def perform
      Spree::ReturnAuthorization.springboard_import_last_day!
    rescue StandardError => error
      ExceptionNotifier.notify_exception(error, data: { msg: 'Import New Returns' })
      raise error
    end
  end
end
