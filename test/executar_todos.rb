# encoding: UTF-8
# Roda todos os testes: ruby test/executar_todos.rb
ok = %w[teste_prancha.rb teste_sketchup.rb].all? do |t|
  puts "\n== #{t}"
  system(RbConfig.ruby, File.join(__dir__, t))
end
exit(ok ? 0 : 1)
