#!/usr/bin/env python3
"""Patch Podfile to set iOS deployment target without adding duplicate post_install."""
import sys

podfile_path = sys.argv[1] if len(sys.argv) > 1 else 'Podfile'
podfile = open(podfile_path).read()

patch_lines = """
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
        config.build_settings['SWIFT_SUPPRESS_WARNINGS'] = 'YES'
        config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      end"""

if 'post_install do |installer|' in podfile:
    # Inject inside existing block
    podfile = podfile.replace(
        'installer.pods_project.targets.each do |target|',
        'installer.pods_project.targets.each do |target|' + patch_lines,
        1  # only first occurrence
    )
    print('Injected into existing post_install block.')
else:
    # No post_install exists, add one
    podfile += (
        '\npost_install do |installer|\n'
        '  installer.pods_project.targets.each do |target|'
        + patch_lines +
        '\n  end\nend\n'
    )
    print('Added new post_install block.')

open(podfile_path, 'w').write(podfile)
print('Podfile patched successfully.')
