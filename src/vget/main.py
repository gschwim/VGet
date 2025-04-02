from kivy.config import Config
Config.set('graphics', 'width', '600')
Config.set('graphics', 'height', '200')
Config.set('graphics', 'resizable', True)

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.label import Label
from kivy.uix.textinput import TextInput
from kivy.uix.button import Button
from kivy.clock import mainthread
import threading
import os
import yt_dlp
import datetime

class DownloadApp(BoxLayout):
    def __init__(self, **kwargs):
        super(DownloadApp, self).__init__(**kwargs)
        self.orientation = 'vertical'
        self.padding = 10
        self.spacing = 10
        
        # Instruction label
        self.add_widget(Label(text='Enter video URL:', size_hint_y=0.2))
        
        # Text input for URL
        self.url_input = TextInput(multiline=False, size_hint_y=0.2)
        self.add_widget(self.url_input)
        
        # Download button
        self.download_button = Button(text='Download', size_hint_y=0.2)
        self.download_button.bind(on_press=self.start_download)
        self.add_widget(self.download_button)
        
        # Status label
        self.status_label = Label(text='', size_hint_y=0.4)
        self.add_widget(self.status_label)

    def start_download(self, instance):
        """Initiate the download process when the button is pressed."""
        url = self.url_input.text.strip()
        if not url:
            self.status_label.text = 'Please enter a URL'
            return
        
        # Update UI to indicate download is starting
        self.status_label.text = 'Preparing to download...'
        self.download_button.disabled = True
        
        # Start download in a separate thread
        thread = threading.Thread(target=self.download_video, args=(url,))
        thread.start()

    def download_video(self, url):
        """Download the video using yt-dlp with progress updates."""
        # Set up the output path with MMDD-hhmm filename
        downloads_path = os.path.expanduser('~/Downloads')
        if not os.path.exists(downloads_path):
            os.makedirs(downloads_path)
        
        now = datetime.datetime.now()
        filename = now.strftime("%m%d-%H%M")
        output_template = os.path.join(downloads_path, f"{filename}.%(ext)s")
        self.status_label.text = f'Preparing to download ...'
        
        # Define progress hook to update UI
        def progress_hook(d):
            if d['status'] == 'downloading':
                percent_str = d.get('_percent_str', 'unknown')
                self.update_status(f'Downloading: {percent_str}')
            elif d['status'] == 'finished':
                self.update_status('Download completed')
        
        # Configure yt-dlp options
        options = {
            'outtmpl': output_template,              # Output file template with MMDD-hhmm
            'cookiesfrombrowser': ('chrome',),       # Use cookies from Chrome
            'progress_hooks': [progress_hook],       # Hook for progress updates
            'quiet': True,                           # Suppress console output
        }
        
        # Perform the download
        try:
            ydl = yt_dlp.YoutubeDL(options)
            ydl.download([url])
        except yt_dlp.DownloadError as e:
            self.update_status(f'Error: {type(e)} - {e}')
        except Exception as e:
            self.update_status(f'Unexpected error: {type(e)} - {e}')
        finally:
            self.enable_button()

    @mainthread
    def update_status(self, message):
        """Update the status label in the main thread."""
        self.status_label.text = message

    @mainthread
    def enable_button(self):
        """Re-enable the download button in the main thread."""
        self.download_button.disabled = False

class VGetApp(App):
    def build(self):
        """Build and return the application's root widget."""
        return DownloadApp()

def main():
    VGetApp().run()

if __name__ == '__main__':
    main()
#
#
#
#
#
#
#
#
#
#
# from kivy.app import App
# from kivy.uix.boxlayout import BoxLayout
# from kivy.uix.label import Label
# from kivy.uix.textinput import TextInput
# from kivy.uix.button import Button
# from kivy.clock import mainthread
# import threading
# import os
# import yt_dlp
#
#
# class DownloadApp(BoxLayout):
#     def __init__(self, **kwargs):
#         super(DownloadApp, self).__init__(**kwargs)
#         self.orientation = 'vertical'
#
#         # Instruction label
#         self.add_widget(Label(text='Enter video URL:'))
#
#         # Text input for URL
#         self.url_input = TextInput(multiline=False)
#         self.add_widget(self.url_input)
#
#         # Download button
#         self.download_button = Button(text='Download')
#         self.download_button.bind(on_press=self.start_download)
#         self.add_widget(self.download_button)
#
#         # Status label
#         self.status_label = Label(text='')
#         self.add_widget(self.status_label)
#
#     def start_download(self, instance):
#         """Initiate the download process when the button is pressed."""
#         url = self.url_input.text.strip()
#         if not url:
#             self.status_label.text = 'Please enter a URL'
#             return
#
#         # Update UI to indicate download is starting
#         self.status_label.text = 'Preparing to download...'
#         self.download_button.disabled = True
#
#         # Start download in a separate thread
#         thread = threading.Thread(target=self.download_video, args=(url,))
#         thread.start()
#
#     def download_video(self, url):
#         """Download the video using yt-dlp with progress updates."""
#         # Set up the output path
#         downloads_path = os.path.expanduser('~/Downloads')
#         if not os.path.exists(downloads_path):
#             os.makedirs(downloads_path)
#
#         output_template = os.path.join(downloads_path, '%(title)s.%(ext)s')
#
#         # Define progress hook to update UI
#         def progress_hook(d):
#             if d['status'] == 'downloading':
#                 percent_str = d.get('_percent_str', 'unknown')
#                 self.update_status(f'Downloading: {percent_str}')
#             elif d['status'] == 'finished':
#                 self.update_status('Download completed')
#
#         # Configure yt-dlp options
#         options = {
#             'outtmpl': output_template,              # Output file template
#             'cookiesfrombrowser': ('chrome',),       # Use cookies from Chrome
#             # Hook for progress updates
#             'progress_hooks': [progress_hook],
#             'quiet': True,                           # Suppress console output
#         }
#
#         # Perform the download
#         try:
#             ydl = yt_dlp.YoutubeDL(options)
#             ydl.download([url])
#         except yt_dlp.DownloadError as e:
#             self.update_status(f'Error: {e}')
#         except Exception as e:
#             self.update_status(f'Unexpected error: {e}')
#         finally:
#             self.enable_button()
#
#     @mainthread
#     def update_status(self, message):
#         """Update the status label in the main thread."""
#         self.status_label.text = message
#
#     @mainthread
#     def enable_button(self):
#         """Re-enable the download button in the main thread."""
#         self.download_button.disabled = False
#
#
# class MyApp(App):
#     def build(self):
#         """Build and return the application's root widget."""
#         return DownloadApp()
#
#
# if __name__ == '__main__':
#     MyApp().run()
