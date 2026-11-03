# encoding: UTF-8
# Empacota a extensão em dist/A3-Detailer-<versão>.rbz
# Uso: ruby tools/build.rb
require 'fileutils'

raiz = File.expand_path('..', __dir__)
src  = File.join(raiz, 'src')
carregador = File.read(File.join(src, 'detalhamento_pm.rb'), encoding: 'UTF-8')
versao = carregador[/ext\.version\s*=\s*'([^']+)'/, 1] or abort('Versão não encontrada em src/detalhamento_pm.rb')

dist = File.join(raiz, 'dist')
FileUtils.mkdir_p(dist)
destino = File.join(dist, "A3-Detailer-#{versao}.rbz")
FileUtils.rm_f(destino)

Dir.chdir(src) do
  if system('zip', '-qr', destino, 'detalhamento_pm.rb', 'detalhamento_pm')
    # ok
  elsif Gem.win_platform?
    tmp = destino.sub(/\.rbz\z/, '.zip')
    cmd = "Compress-Archive -Path 'detalhamento_pm.rb','detalhamento_pm' -DestinationPath '#{tmp}' -Force"
    system('powershell', '-NoProfile', '-Command', cmd) or abort('Falha ao compactar')
    FileUtils.mv(tmp, destino)
  else
    abort("Instale o 'zip' para empacotar.")
  end
end
puts "Gerado: #{destino}"
