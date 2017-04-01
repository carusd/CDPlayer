
Pod::Spec.new do |s|
  s.name             = 'CDPlayer'
  s.version          = '1.3.0'
  s.summary          = 'A player that can be caching the playing video'


  s.description      = <<-DESC
                        A player made of iOS API, support cache in playing.
                        Allow you to initiate and dispatch multi download task.
                        
                        DESC

  s.homepage         = 'https://github.com/carusd/CDPlayer'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'carusd' => 'carusd@gmail.com' }
  s.source           = { :git => 'https://github.com/carusd/CDPlayer.git', :tag => s.version.to_s, :submodules => true }

  s.ios.deployment_target = '8.0'

  s.source_files = 'CDPlayer/*.{h,m}'

  s.dependency 'AFNetworking'
end
