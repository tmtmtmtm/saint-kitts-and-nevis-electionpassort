#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'creek'
require 'tempfile'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

require 'pry'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

class CreekTable

  def initialize(filename)
    @_filename = filename
  end

  def data
    @_data ||= converted_first_sheet
  end

  private
  def book
    @_book ||= Creek::Book.new(@_filename, check_file_extension: false)
  end

  def columns
    header_row.values
  end

  def header_row
    @_header ||= Hash[first_sheet.rows.first.map { |cell, title| [cell_column(cell), title] }]
  end

  def first_sheet
    book.sheets.first
  end

  def converted_first_sheet
    mapping = header_row
    first_sheet.rows.drop(1).map do |r|
      Hash[ r.reject { |_, v| v.nil? }.map { |cell, value| [ mapping[cell_column(cell)], value.to_s.tidy] } ]
    end
  end

  def cell_column(cell)
    cell.sub(/[[:digit:]]+/,'')
  end

end

url = 'http://www.electionpassport.com/files/KN/KN.xlsx'
spreadsheet = Tempfile.new(['spreadsheet', '.xslx'])
IO.copy_stream(open(url), spreadsheet)

table = CreekTable.new(spreadsheet).data

results = table.map do |row|
  parties = row.keys.select { |k| k.end_with? '_C' }.map { |k| k.chomp('_C') }
  results = parties.map do |p|
    {
      candidate: row.delete(p + "_C"),
      party: p,
      votes: row.delete(p + "_V"),
    }
  end

  row.merge({ 
    results: results,
    winner: results.max_by { |h| h[:votes].to_i },
  })
end


id = Hash.new(0)
results.reject { |r| r['CON_NAME'].to_s.empty? }.each do |r|
  data = {
    id: "%s-%d" % [r['YEAR'], id[r['YEAR']] += 1],
    name: r[:winner][:candidate],
    party: r[:winner][:party].sub(/\d+$/,''),
    area_id: "%s-%d" % [r['YEAR'], r['CON_NO'].sub(/\D+/,'')],
    area: r['CON_NAME'],
    election: r['YEAR']
  } 
  ScraperWiki.save_sqlite([:id], data)
end

