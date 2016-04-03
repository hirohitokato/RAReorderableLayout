Pod::Spec.new do |s|
  s.name         = "RAReorderableLayout"
  s.version      = "0.4.0-hirohitokato-0.1.0"
  s.summary      = "A UICollectionView layout which you can move items with drag and drop."
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.homepage     = "https://github.com/hirohitokato"
  s.author       = { "ra1028" => "r.fe51028.r@gmail.com",
                     "hirohitokato" => "hkato193@gmail.com" }
  s.platform     = :ios, '8.0'
  s.source       = { :git => "https://github.com/hirohitokato/RAReorderableLayout.git",
                     :tag => s.version.to_s }
  s.requires_arc = true
  s.source_files =  'RAReorderableLayout/*.swift'
end
